use std::fs::OpenOptions;
use std::io::{self, Write, Seek, SeekFrom};
use std::path::Path;
use std::os::unix::io::AsRawFd;
use qrcode::QrCode;
use font8x8::{UnicodeFonts, BASIC_FONTS};

#[cfg(feature = "image-output")]
use image::{RgbImage, ImageBuffer, Rgb};

// Embed the logo bitmap generated at build time
const LOGO_WIDTH: usize = 223;
const LOGO_HEIGHT: usize = 89;
const LOGO_DATA: &[u8] = include_bytes!(concat!(env!("OUT_DIR"), "/clan-logo.rgba"));

#[derive(Clone, Copy, Debug)]
struct Color {
    r: u8,
    g: u8,
    b: u8,
}

struct FramebufferConfig {
    width: usize,          // Visible width (xres)
    height: usize,         // Visible height (yres)
    stride: usize,         // Line stride in pixels (xres_virtual)
    bytes_per_pixel: usize,
    red_offset: usize,
    green_offset: usize,
    blue_offset: usize,
}

const FB_PATH: &str = "/dev/fb0";

#[repr(C)]
#[derive(Default)]
struct FbVarScreeninfo {
    xres: u32,
    yres: u32,
    xres_virtual: u32,
    yres_virtual: u32,
    xoffset: u32,
    yoffset: u32,
    bits_per_pixel: u32,
    grayscale: u32,
    red: FbBitfield,
    green: FbBitfield,
    blue: FbBitfield,
    transp: FbBitfield,
    nonstd: u32,
    activate: u32,
    height: u32,
    width: u32,
    accel_flags: u32,
    pixclock: u32,
    left_margin: u32,
    right_margin: u32,
    upper_margin: u32,
    lower_margin: u32,
    hsync_len: u32,
    vsync_len: u32,
    sync: u32,
    vmode: u32,
    rotate: u32,
    colorspace: u32,
    reserved: [u32; 4],
}

#[repr(C)]
#[derive(Default)]
struct FbBitfield {
    offset: u32,
    length: u32,
    msb_right: u32,
}

/// Safe RAII wrapper for memory-mapped framebuffer
/// Automatically calls munmap on drop
struct FramebufferMap {
    ptr: *mut u8,
    size: usize,
}

impl FramebufferMap {
    /// Create a new memory-mapped framebuffer
    ///
    /// # Safety
    /// The file descriptor must be valid and represent a framebuffer device
    unsafe fn new(fd: std::os::unix::io::RawFd, size: usize) -> io::Result<Self> {
        let ptr = libc::mmap(
            std::ptr::null_mut(),
            size,
            libc::PROT_READ | libc::PROT_WRITE,
            libc::MAP_SHARED,  // MAP_SHARED ensures changes are visible to display controller
            fd,
            0,
        );

        if ptr == libc::MAP_FAILED {
            return Err(io::Error::last_os_error());
        }

        Ok(FramebufferMap {
            ptr: ptr as *mut u8,
            size,
        })
    }

    /// Get a mutable slice to the mapped memory
    fn as_slice_mut(&mut self) -> &mut [u8] {
        unsafe { std::slice::from_raw_parts_mut(self.ptr, self.size) }
    }

    /// Sync the mapped memory to the device
    /// This flushes CPU caches and ensures changes are visible to hardware
    fn sync(&self) -> io::Result<()> {
        let result = unsafe {
            libc::msync(
                self.ptr as *mut libc::c_void,
                self.size,
                libc::MS_SYNC,  // MS_SYNC blocks until data is written to device
            )
        };

        if result == 0 {
            Ok(())
        } else {
            Err(io::Error::last_os_error())
        }
    }
}

impl Drop for FramebufferMap {
    fn drop(&mut self) {
        unsafe {
            libc::munmap(self.ptr as *mut libc::c_void, self.size);
        }
    }
}

fn main() -> io::Result<()> {
    let args: Vec<String> = std::env::args().collect();

    // Check for --debug-fb argument
    if args.len() > 1 && args[1] == "--debug-fb" {
        return print_framebuffer_info();
    }

    // Check for --output-image argument
    #[cfg(feature = "image-output")]
    if args.len() > 1 && args[1] == "--output-image" {
        let output_path = if args.len() > 2 {
            args[2].clone()
        } else {
            "network-status.png".to_string()
        };
        return render_to_image(&output_path);
    }

    #[cfg(not(feature = "image-output"))]
    if args.len() > 1 && args[1] == "--output-image" {
        eprintln!("Error: image-output feature not enabled in this build");
        eprintln!("Build with --features image-output to use this feature");
        return Err(io::Error::new(io::ErrorKind::Other, "image-output feature not enabled"));
    }

    // Check if framebuffer is available
    if Path::new(FB_PATH).exists() {
        // Try framebuffer display
        if display_on_framebuffer().is_ok() {
            return Ok(());
        }
    }

    // Fall back to terminal display
    display_in_terminal()
}

fn print_framebuffer_info() -> io::Result<()> {
    if !Path::new(FB_PATH).exists() {
        eprintln!("Error: Framebuffer device {} not found", FB_PATH);
        return Err(io::Error::new(io::ErrorKind::NotFound, "framebuffer not found"));
    }

    let fb = OpenOptions::new()
        .read(true)
        .write(false)
        .open(FB_PATH)?;

    let mut vinfo: FbVarScreeninfo = Default::default();
    unsafe {
        let ret = libc::ioctl(fb.as_raw_fd(), 0x4600, &mut vinfo);
        if ret < 0 {
            return Err(io::Error::last_os_error());
        }
    }

    println!("=== Framebuffer Information ===");
    println!();
    println!("Display Resolution:");
    println!("  xres (visible width):     {} pixels", vinfo.xres);
    println!("  yres (visible height):    {} pixels", vinfo.yres);
    println!("  xres_virtual (stride):    {} pixels", vinfo.xres_virtual);
    println!("  yres_virtual:             {} pixels", vinfo.yres_virtual);
    println!();
    println!("Virtual Display Offset:");
    println!("  xoffset:                  {}", vinfo.xoffset);
    println!("  yoffset:                  {}", vinfo.yoffset);
    println!();
    println!("Color Configuration:");
    println!("  bits_per_pixel:           {}", vinfo.bits_per_pixel);
    println!("  bytes_per_pixel:          {}", vinfo.bits_per_pixel / 8);
    println!("  grayscale:                {}", vinfo.grayscale);
    println!();
    println!("Color Component Layout:");
    println!("  Red    - offset: {:2} bits, length: {:2} bits, msb_right: {}",
             vinfo.red.offset, vinfo.red.length, vinfo.red.msb_right);
    println!("  Green  - offset: {:2} bits, length: {:2} bits, msb_right: {}",
             vinfo.green.offset, vinfo.green.length, vinfo.green.msb_right);
    println!("  Blue   - offset: {:2} bits, length: {:2} bits, msb_right: {}",
             vinfo.blue.offset, vinfo.blue.length, vinfo.blue.msb_right);
    println!("  Transp - offset: {:2} bits, length: {:2} bits, msb_right: {}",
             vinfo.transp.offset, vinfo.transp.length, vinfo.transp.msb_right);
    println!();

    // Determine pixel format
    let format = if vinfo.red.offset == 0 && vinfo.green.offset == 8 && vinfo.blue.offset == 16 {
        "RGB"
    } else if vinfo.blue.offset == 0 && vinfo.green.offset == 8 && vinfo.red.offset == 16 {
        "BGR"
    } else if vinfo.red.offset == 16 && vinfo.green.offset == 8 && vinfo.blue.offset == 0 && vinfo.transp.offset == 24 {
        "BGRA"
    } else if vinfo.blue.offset == 16 && vinfo.green.offset == 8 && vinfo.red.offset == 0 && vinfo.transp.offset == 24 {
        "RGBA"
    } else {
        "Custom/Unknown"
    };
    println!("  Detected format:          {}", format);
    println!();

    println!("Timing (for reference):");
    println!("  pixclock:                 {}", vinfo.pixclock);
    println!("  left_margin:              {}", vinfo.left_margin);
    println!("  right_margin:             {}", vinfo.right_margin);
    println!("  upper_margin:             {}", vinfo.upper_margin);
    println!("  lower_margin:             {}", vinfo.lower_margin);
    println!("  hsync_len:                {}", vinfo.hsync_len);
    println!("  vsync_len:                {}", vinfo.vsync_len);
    println!();

    println!("Other:");
    println!("  nonstd:                   {}", vinfo.nonstd);
    println!("  activate:                 {}", vinfo.activate);
    println!("  vmode:                    {}", vinfo.vmode);
    println!("  rotate:                   {} (0=normal, 1=90°, 2=180°, 3=270°)", vinfo.rotate);
    println!();

    // Calculate memory requirements
    let line_size = vinfo.xres_virtual * (vinfo.bits_per_pixel / 8);
    let total_size = line_size * vinfo.yres_virtual;
    println!("Memory Layout:");
    println!("  Line size (stride):       {} bytes", line_size);
    println!("  Total framebuffer size:   {} bytes ({:.2} MB)",
             total_size, total_size as f64 / 1024.0 / 1024.0);

    // Check for padding
    let expected_line_size = vinfo.xres * (vinfo.bits_per_pixel / 8);
    if line_size > expected_line_size {
        let padding = line_size - expected_line_size;
        println!("  ⚠ Line padding detected:  {} bytes per line", padding);
        println!("                            (xres_virtual > xres, must use stride for addressing)");
    } else {
        println!("  ✓ No line padding detected");
    }

    Ok(())
}

struct DisplayState {
    root_password: String,
    onion_hostname: String,
    login_json: String,
    ip_addrs: Vec<String>,
    hostname: String,
}

impl DisplayState {
    fn read_current() -> Self {
        let root_password = std::fs::read_to_string("/var/shared/root-password")
            .unwrap_or_else(|_| "(waiting...)".to_string())
            .trim()
            .to_string();

        // Read tor onion hostname directly from tor data directory
        let onion_hostname = std::fs::read_to_string("/var/lib/tor/onion/hidden-ssh/hostname")
            .unwrap_or_else(|_| "(waiting for tor...)".to_string())
            .trim()
            .to_string();

        let ip_addrs = get_ip_addresses();
        let hostname = get_hostname();

        // Generate login JSON in memory for QR code
        let login_json = generate_login_json(&root_password, &onion_hostname, &ip_addrs);

        DisplayState {
            root_password,
            onion_hostname,
            login_json,
            ip_addrs,
            hostname,
        }
    }

    fn has_changed(&self, other: &DisplayState) -> bool {
        self.root_password != other.root_password
            || self.onion_hostname != other.onion_hostname
            || self.login_json != other.login_json
            || self.ip_addrs != other.ip_addrs
            || self.hostname != other.hostname
    }
}

fn calculate_qr_layout(fb_config: &FramebufferConfig, qr_code: &QrCode) -> (usize, usize, usize, usize) {
    let qr_size = qr_code.width();
    let quiet_zone = 4;
    let qr_with_quiet = qr_size + (quiet_zone * 2);

    // Reserve space for text (approximately 400 pixels)
    let available_height = fb_config.height.saturating_sub(400);
    let scale = std::cmp::min(
        fb_config.width / (qr_with_quiet * 2),
        available_height / qr_with_quiet
    ).max(1); // Ensure scale is at least 1

    let qr_pixel_size = qr_size * scale;
    let quiet_zone_pixels = quiet_zone * scale;
    let total_size = qr_pixel_size + (quiet_zone_pixels * 2);
    let x_offset = (fb_config.width - total_size) / 2 + quiet_zone_pixels;
    let y_offset = 80 + quiet_zone_pixels;

    (qr_size, qr_pixel_size, x_offset, y_offset)
}

fn display_on_framebuffer() -> io::Result<()> {
    let mut current_state = DisplayState::read_current();

    // Generate QR code (use placeholder if not available yet)
    let mut code = QrCode::new(&current_state.login_json)
        .unwrap_or_else(|_| QrCode::new(r#"{"status": "waiting"}"#).unwrap());

    // Open framebuffer
    let fb = OpenOptions::new()
        .read(true)
        .write(true)
        .open(FB_PATH)?;

    // Get screen info
    let mut vinfo: FbVarScreeninfo = Default::default();
    unsafe {
        let ret = libc::ioctl(fb.as_raw_fd(), 0x4600, &mut vinfo);
        if ret < 0 {
            return Err(io::Error::last_os_error());
        }
    }

    let fb_config = FramebufferConfig {
        width: vinfo.xres as usize,
        height: vinfo.yres as usize,
        stride: vinfo.xres_virtual as usize,
        bytes_per_pixel: (vinfo.bits_per_pixel / 8) as usize,
        red_offset: (vinfo.red.offset / 8) as usize,
        green_offset: (vinfo.green.offset / 8) as usize,
        blue_offset: (vinfo.blue.offset / 8) as usize,
    };

    // Memory map the framebuffer instead of using write()
    // This is the standard approach - see kernel fb.h: write() is for "strange non linear layouts"
    let screen_size = fb_config.stride * fb_config.height * fb_config.bytes_per_pixel;

    // Create safe RAII wrapper for mmap - automatically unmaps on drop
    let mut fb_map = unsafe { FramebufferMap::new(fb.as_raw_fd(), screen_size)? };

    // Initial render
    let (mut qr_size, mut qr_pixel_size, mut x_offset, mut y_offset) = calculate_qr_layout(&fb_config, &code);
    render_display(fb_map.as_slice_mut(), &fb_config, &code, qr_size, qr_pixel_size, x_offset, y_offset, &current_state);

    // Ensure changes are visible to hardware (flush CPU cache)
    // MS_SYNC ensures the call blocks until the data is actually written to the device
    fb_map.sync()?;

    // Poll for changes and redraw only when needed
    loop {
        std::thread::sleep(std::time::Duration::from_secs(2));

        let new_state = DisplayState::read_current();
        if new_state.has_changed(&current_state) {
            // Update QR code if login.json changed
            if new_state.login_json != current_state.login_json {
                code = QrCode::new(&new_state.login_json)
                    .unwrap_or_else(|_| QrCode::new(r#"{"status": "waiting"}"#).unwrap());

                // Recalculate layout for the new QR code size
                let layout = calculate_qr_layout(&fb_config, &code);
                qr_size = layout.0;
                qr_pixel_size = layout.1;
                x_offset = layout.2;
                y_offset = layout.3;
            }

            render_display(fb_map.as_slice_mut(), &fb_config, &code, qr_size, qr_pixel_size, x_offset, y_offset, &new_state);

            // Sync to ensure display controller sees the changes
            fb_map.sync()?;

            current_state = new_state;
        }
    }
}

fn render_display(
    buffer: &mut [u8],
    fb_config: &FramebufferConfig,
    code: &QrCode,
    qr_size: usize,
    qr_pixel_size: usize,
    x_offset: usize,
    y_offset: usize,
    state: &DisplayState,
) {
    // Clear buffer (black background)
    buffer.fill(0);

    let scale = qr_pixel_size / qr_size;
    let quiet_zone = 4;
    let quiet_zone_pixels = quiet_zone * scale;
    let total_size = qr_pixel_size + (quiet_zone_pixels * 2);

    // Draw white quiet zone (background for QR code)
    let qz_start_x = x_offset - quiet_zone_pixels;
    let qz_start_y = y_offset - quiet_zone_pixels;
    for qz_y in 0..total_size {
        for qz_x in 0..total_size {
            let px = qz_start_x + qz_x;
            let py = qz_start_y + qz_y;

            if px < fb_config.width && py < fb_config.height {
                let offset = (py * fb_config.stride + px) * fb_config.bytes_per_pixel;
                buffer[offset + fb_config.red_offset] = 0xFF;
                buffer[offset + fb_config.green_offset] = 0xFF;
                buffer[offset + fb_config.blue_offset] = 0xFF;
                if fb_config.bytes_per_pixel > 3 {
                    buffer[offset + 3] = 0xFF;
                }
            }
        }
    }

    // Draw QR code on white background
    for y in 0..qr_size {
        for x in 0..qr_size {
            let module = code[(x, y)];
            let color = if module == qrcode::Color::Dark { 0x00 } else { 0xFF };

            // Draw scaled pixel
            for dy in 0..scale {
                for dx in 0..scale {
                    let px = x_offset + (x * scale) + dx;
                    let py = y_offset + (y * scale) + dy;

                    if px < fb_config.width && py < fb_config.height {
                        let offset = (py * fb_config.stride + px) * fb_config.bytes_per_pixel;
                        buffer[offset + fb_config.red_offset] = color;
                        buffer[offset + fb_config.green_offset] = color;
                        buffer[offset + fb_config.blue_offset] = color;
                        if fb_config.bytes_per_pixel > 3 {
                            buffer[offset + 3] = 0xFF;
                        }
                    }
                }
            }
        }
    }

    // Draw logo in top-left corner as branding
    let logo_x = 30;
    let logo_y = 30;
    draw_logo(buffer, fb_config, logo_x, logo_y);

    // Draw text information below QR code with better styling
    let text_y_start = y_offset + qr_pixel_size + 50;
    let line_height = 22;
    let section_spacing = 30;
    let left_margin = 50;
    let indent = 70;

    // Section 1: Login Credentials
    draw_text(buffer, fb_config,
              "Login Credentials", left_margin, text_y_start);

    draw_text(buffer, fb_config,
              &format!("  Root password: {}", state.root_password), left_margin, text_y_start + section_spacing);

    // Section 2: Network Information
    let network_section_y = text_y_start + section_spacing * 2;
    draw_text(buffer, fb_config,
              "Network Information", left_margin, network_section_y);

    // Draw IP addresses with colors
    let mut line_offset = 1;
    for addr in state.ip_addrs.iter() {
        let lines_used = draw_colored_line(buffer, fb_config,
                         addr, indent, network_section_y + section_spacing + line_height * line_offset);
        line_offset += lines_used;
    }

    // Section 3: Remote Access
    let remote_section_y = network_section_y + section_spacing + line_height * line_offset + 10;
    draw_text(buffer, fb_config,
              "Remote Access", left_margin, remote_section_y);

    draw_text(buffer, fb_config,
              &format!("  Tor Hidden Service: {}", state.onion_hostname),
              left_margin, remote_section_y + section_spacing);
    draw_text(buffer, fb_config,
              &format!("  Multicast DNS: {}.local", state.hostname),
              left_margin, remote_section_y + section_spacing + line_height);

    // Footer
    let footer_y = remote_section_y + section_spacing + line_height * 2 + 20;
    draw_separator_line(buffer, fb_config, left_margin, footer_y, fb_config.width - 100);
    draw_text(buffer, fb_config,
              "Press 'Ctrl-C' for console access",
              left_margin, footer_y + 20);
}

fn display_in_terminal() -> io::Result<()> {
    let mut current_state = DisplayState::read_current();

    // Initial display
    print_terminal_output(&current_state);

    // Poll for changes and check if framebuffer becomes available
    loop {
        std::thread::sleep(std::time::Duration::from_secs(2));

        // Check if framebuffer became available
        if Path::new(FB_PATH).exists() {
            if display_on_framebuffer().is_ok() {
                return Ok(());
            }
        }

        let new_state = DisplayState::read_current();
        if new_state.has_changed(&current_state) {
            // Clear screen and redraw
            print!("\x1B[2J\x1B[H"); // ANSI clear screen and move cursor to home
            print_terminal_output(&new_state);
            current_state = new_state;
        }
    }
}

fn print_terminal_output(state: &DisplayState) {
    println!("Login Credentials");
    println!("  Root password: {}", state.root_password);
    println!();
    println!("Network Information");
    for addr in &state.ip_addrs {
        println!("  {}", addr);
    }
    println!();
    println!("Remote Access");
    println!("  Tor Hidden Service: {}", state.onion_hostname);
    println!("  Multicast DNS: {}.local", state.hostname);
    println!();
    println!("{}",  "─".repeat(80));
    println!("Press 'Ctrl-C' for console access");
}

fn print_network_addresses() {
    if let Ok(output) = std::process::Command::new("ip")
        .args(["-brief", "-color", "addr"])
        .output()
    {
        if let Ok(stdout) = String::from_utf8(output.stdout) {
            for line in stdout.lines() {
                if !line.contains("127.0.0.1") {
                    println!("{}", line);
                }
            }
        }
    }
}

fn get_hostname() -> String {
    std::fs::read_to_string("/etc/hostname")
        .unwrap_or_else(|_| "nixos".to_string())
        .trim()
        .to_string()
}

fn escape_json_string(s: &str) -> String {
    s.replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\n', "\\n")
        .replace('\r', "\\r")
        .replace('\t', "\\t")
}

fn generate_login_json(password: &str, onion: &str, ip_addrs: &[String]) -> String {
    // Extract just IP addresses (not the full line with interface name)
    let addrs: Vec<String> = ip_addrs
        .iter()
        .flat_map(|line| {
            // Parse lines like: "wlp192s0 UP 192.168.1.1/24 2001:db8::1/64"
            let parts: Vec<&str> = line.split_whitespace().collect();
            parts.into_iter()
                .skip(2) // Skip interface name and status
                .filter(|p| p.contains('.') || p.contains(':')) // Only IP addresses
                .map(|addr| {
                    // Remove CIDR suffix
                    addr.split('/').next().unwrap_or(addr).to_string()
                })
                .collect::<Vec<_>>()
        })
        .collect();

    // Generate JSON manually
    let mut json = String::from("{");
    json.push_str(&format!("\"pass\":\"{}\",", escape_json_string(password)));
    json.push_str(&format!("\"tor\":\"{}\",", escape_json_string(onion)));
    json.push_str("\"addrs\":[");

    for (i, addr) in addrs.iter().enumerate() {
        if i > 0 {
            json.push(',');
        }
        json.push_str(&format!("\"{}\"", escape_json_string(addr)));
    }

    json.push_str("]}");
    json
}

fn get_ip_addresses() -> Vec<String> {
    let mut addrs = Vec::new();
    if let Ok(output) = std::process::Command::new("ip")
        .args(["-brief", "-color", "addr"])
        .output()
    {
        if let Ok(stdout) = String::from_utf8(output.stdout) {
            for line in stdout.lines() {
                if !line.contains("127.0.0.1") && line.contains("UP") {
                    addrs.push(line.to_string());
                }
            }
        }
    }
    addrs
}

struct TextSegment {
    text: String,
    color: Color,
}

fn parse_colored_text(text: &str) -> Vec<TextSegment> {
    let mut segments = Vec::new();
    let mut current_text = String::new();
    let mut current_color = Color { r: 255, g: 255, b: 255 }; // White default
    let mut chars = text.chars().peekable();

    while let Some(ch) = chars.next() {
        if ch == '\x1b' && chars.peek() == Some(&'[') {
            // Save current segment if there's text
            if !current_text.is_empty() {
                segments.push(TextSegment {
                    text: current_text.clone(),
                    color: current_color,
                });
                current_text.clear();
            }

            chars.next(); // consume '['
            let mut code = String::new();

            // Read until 'm'
            while let Some(c) = chars.next() {
                if c == 'm' {
                    break;
                }
                code.push(c);
            }

            // Parse color code
            current_color = match code.as_str() {
                "0" | "00" => Color { r: 255, g: 255, b: 255 }, // Reset to white
                "1" | "01" => Color { r: 255, g: 255, b: 255 }, // Bold (keep current)
                "30" => Color { r: 0, g: 0, b: 0 },              // Black
                "31" | "1;31" => Color { r: 255, g: 85, b: 85 }, // Red
                "32" | "1;32" => Color { r: 85, g: 255, b: 85 }, // Green
                "33" | "1;33" => Color { r: 255, g: 255, b: 85 }, // Yellow
                "34" | "1;34" => Color { r: 85, g: 85, b: 255 }, // Blue
                "35" | "1;35" => Color { r: 255, g: 85, b: 255 }, // Magenta
                "36" | "1;36" => Color { r: 85, g: 255, b: 255 }, // Cyan
                "37" | "1;37" => Color { r: 255, g: 255, b: 255 }, // White
                _ => current_color, // Keep current color for unknown codes
            };
        } else {
            current_text.push(ch);
        }
    }

    // Add final segment
    if !current_text.is_empty() {
        segments.push(TextSegment {
            text: current_text,
            color: current_color,
        });
    }

    segments
}

#[cfg(feature = "image-output")]
fn render_to_image(output_path: &str) -> io::Result<()> {
    let state = DisplayState::read_current();

    // Generate QR code (use placeholder if not available yet)
    let code = QrCode::new(&state.login_json)
        .unwrap_or_else(|_| QrCode::new(r#"{"status": "waiting"}"#).unwrap());
    let qr_size = code.width();

    // Image dimensions - use BGR format like typical framebuffers
    let fb_config = FramebufferConfig {
        width: 1920,
        height: 1080,
        stride: 1920,     // No padding for generated images
        bytes_per_pixel: 4,
        red_offset: 2,    // BGR format: Red at offset 2
        green_offset: 1,  // Green at offset 1
        blue_offset: 0,   // Blue at offset 0
    };

    // Calculate QR code scaling with quiet zone (4 modules on each side per spec)
    let quiet_zone = 4;
    let qr_with_quiet = qr_size + (quiet_zone * 2);

    // Reserve space for text (approximately 400 pixels)
    let available_height = fb_config.height.saturating_sub(400);
    let scale = std::cmp::min(
        fb_config.width / (qr_with_quiet * 2),
        available_height / qr_with_quiet
    ).max(1);

    let qr_pixel_size = qr_size * scale;
    let quiet_zone_pixels = quiet_zone * scale;
    let total_size = qr_pixel_size + (quiet_zone_pixels * 2);
    let x_offset = (fb_config.width - total_size) / 2 + quiet_zone_pixels;
    let y_offset = 80 + quiet_zone_pixels;

    // Create buffer and render display
    let mut buffer = vec![0u8; fb_config.stride * fb_config.height * fb_config.bytes_per_pixel];
    render_display(&mut buffer, &fb_config, &code, qr_size, qr_pixel_size, x_offset, y_offset, &state);

    // Convert buffer to RGB for image crate
    let mut img: RgbImage = ImageBuffer::new(fb_config.width as u32, fb_config.height as u32);
    for y in 0..fb_config.height {
        for x in 0..fb_config.width {
            let offset = (y * fb_config.stride + x) * fb_config.bytes_per_pixel;
            let r = buffer[offset + fb_config.red_offset];
            let g = buffer[offset + fb_config.green_offset];
            let b = buffer[offset + fb_config.blue_offset];
            img.put_pixel(x as u32, y as u32, Rgb([r, g, b]));
        }
    }

    // Save the image
    img.save(output_path).map_err(|e| io::Error::new(io::ErrorKind::Other, e))?;

    println!("Image saved to: {}", output_path);
    Ok(())
}

fn draw_text(buffer: &mut [u8], fb_config: &FramebufferConfig, text: &str, x: usize, y: usize) {
    draw_colored_text(buffer, fb_config, text, x, y, Color { r: 255, g: 255, b: 255 });
}

fn draw_separator_line(buffer: &mut [u8], fb_config: &FramebufferConfig, x: usize, y: usize, length: usize) {
    let color = Color { r: 100, g: 100, b: 100 }; // Gray color
    let line_thickness = 2;

    for thickness in 0..line_thickness {
        for i in 0..length {
            let px = x + i;
            let py = y + thickness;

            if px < fb_config.width && py < fb_config.height {
                let offset = (py * fb_config.stride + px) * fb_config.bytes_per_pixel;
                buffer[offset + fb_config.red_offset] = color.r;
                buffer[offset + fb_config.green_offset] = color.g;
                buffer[offset + fb_config.blue_offset] = color.b;
                if fb_config.bytes_per_pixel > 3 {
                    buffer[offset + 3] = 0xFF;
                }
            }
        }
    }
}

fn draw_colored_text(buffer: &mut [u8], fb_config: &FramebufferConfig, text: &str, x: usize, y: usize, color: Color) {
    let scale = 2; // Make text 2x larger for better readability

    for (char_idx, ch) in text.chars().enumerate() {
        if let Some(glyph) = BASIC_FONTS.get(ch) {
            let char_x = x + char_idx * 8 * scale;

            // Draw each pixel of the character
            for (row_idx, row) in glyph.iter().enumerate() {
                for col in 0..8 {
                    if row & (1 << col) != 0 {
                        // Draw scaled pixel
                        for dy in 0..scale {
                            for dx in 0..scale {
                                let px = char_x + col * scale + dx;
                                let py = y + row_idx * scale + dy;

                                if px < fb_config.width && py < fb_config.height {
                                    let offset = (py * fb_config.stride + px) * fb_config.bytes_per_pixel;
                                    buffer[offset + fb_config.red_offset] = color.r;
                                    buffer[offset + fb_config.green_offset] = color.g;
                                    buffer[offset + fb_config.blue_offset] = color.b;
                                    if fb_config.bytes_per_pixel > 3 {
                                        buffer[offset + 3] = 0xFF; // Alpha
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

fn draw_logo(buffer: &mut [u8], fb_config: &FramebufferConfig, x: usize, y: usize) {
    // Draw white background rectangle with some padding
    let padding = 10;
    for bg_y in 0..(LOGO_HEIGHT + 2 * padding) {
        for bg_x in 0..(LOGO_WIDTH + 2 * padding) {
            let px = x.saturating_sub(padding) + bg_x;
            let py = y.saturating_sub(padding) + bg_y;

            if px < fb_config.width && py < fb_config.height {
                let offset = (py * fb_config.stride + px) * fb_config.bytes_per_pixel;
                buffer[offset + fb_config.red_offset] = 0xFF;
                buffer[offset + fb_config.green_offset] = 0xFF;
                buffer[offset + fb_config.blue_offset] = 0xFF;
                if fb_config.bytes_per_pixel > 3 {
                    buffer[offset + 3] = 0xFF;
                }
            }
        }
    }

    // Draw logo on top of white background
    for logo_y in 0..LOGO_HEIGHT {
        for logo_x in 0..LOGO_WIDTH {
            let logo_offset = (logo_y * LOGO_WIDTH + logo_x) * 4; // RGBA format
            let r = LOGO_DATA[logo_offset];
            let g = LOGO_DATA[logo_offset + 1];
            let b = LOGO_DATA[logo_offset + 2];
            let a = LOGO_DATA[logo_offset + 3];

            // Only draw if not fully transparent
            if a > 0 {
                let px = x + logo_x;
                let py = y + logo_y;

                if px < fb_config.width && py < fb_config.height {
                    let offset = (py * fb_config.stride + px) * fb_config.bytes_per_pixel;
                    buffer[offset + fb_config.red_offset] = r;
                    buffer[offset + fb_config.green_offset] = g;
                    buffer[offset + fb_config.blue_offset] = b;
                    if fb_config.bytes_per_pixel > 3 {
                        buffer[offset + 3] = a; // Alpha
                    }
                }
            }
        }
    }
}

fn draw_colored_line(buffer: &mut [u8], fb_config: &FramebufferConfig, text: &str, x: usize, y: usize) -> usize {
    let segments = parse_colored_text(text);
    let scale = 2;
    let char_width = 8 * scale;
    let line_height = 20;
    let max_width = fb_config.width - 100;
    let mut current_x = x;
    let mut lines_used = 0;

    for segment in segments {
        let segment_width = segment.text.len() * char_width;

        // Check if we need to wrap
        if current_x + segment_width > x + max_width && current_x > x {
            // Move to next line
            lines_used += 1;
            current_x = x + 20; // Indent wrapped lines
        }

        draw_colored_text(buffer, fb_config, &segment.text, current_x, y + (lines_used * line_height), segment.color);
        current_x += segment_width;
    }

    lines_used + 1 // Return number of lines used
}
