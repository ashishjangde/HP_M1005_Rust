//! M1005 ASP scanner protocol, following SANE hpljm1005 by Philippe Rétornaz.
//! GPL-2.0-or-later; see THIRD_PARTY.md for the upstream source and notices.
use crate::Result;
use std::{
    ffi::{CString, c_void},
    path::{Path, PathBuf},
    ptr::NonNull,
    sync::atomic::{AtomicBool, Ordering},
    time::{Duration, Instant},
};

const MAGIC: u32 = 0x41535001;
const MAX_PACKET: usize = 16 * 1024 * 1024;
static CANCELED: AtomicBool = AtomicBool::new(false);

unsafe extern "C" {
    fn hp_scanner_open(error: *mut u32) -> *mut c_void;
    fn hp_scanner_read(context: *mut c_void, data: *mut u8, length: *mut u32) -> u32;
    fn hp_scanner_write(context: *mut c_void, data: *const u8, length: u32) -> u32;
    fn hp_scanner_close(context: *mut c_void);
    fn hp_scanner_save(
        pixels: *const u8,
        width: u32,
        height: u32,
        channels: u32,
        dpi: u32,
        path: *const std::ffi::c_char,
        pdf: i32,
    ) -> i32;
    fn signal(number: i32, handler: extern "C" fn(i32)) -> usize;
}

extern "C" fn interrupt(_: i32) {
    CANCELED.store(true, Ordering::Relaxed);
}

pub trait Transport {
    fn write(&mut self, bytes: &[u8]) -> Result<()>;
    fn read(&mut self, bytes: &mut [u8]) -> Result<usize>;
}

pub struct Usb {
    handle: NonNull<c_void>,
}
impl Usb {
    pub fn open() -> Result<Self> {
        let mut code = 0;
        let handle = NonNull::new(unsafe { hp_scanner_open(&mut code) })
            .ok_or_else(|| format!("cannot open M1005 scanner interface (IOKit 0x{code:08x}). Check USB, power, and that no other scan is running"))?;
        Ok(Self { handle })
    }
}
impl Transport for Usb {
    fn write(&mut self, bytes: &[u8]) -> Result<()> {
        let code =
            unsafe { hp_scanner_write(self.handle.as_ptr(), bytes.as_ptr(), bytes.len() as u32) };
        if code != 0 {
            return Err(format!("USB scanner write failed: 0x{code:08x}").into());
        }
        Ok(())
    }
    fn read(&mut self, bytes: &mut [u8]) -> Result<usize> {
        let mut length = bytes.len() as u32;
        let code =
            unsafe { hp_scanner_read(self.handle.as_ptr(), bytes.as_mut_ptr(), &mut length) };
        if code != 0 {
            return Err(format!("USB scanner read failed: 0x{code:08x}").into());
        }
        if length as usize > bytes.len() {
            return Err("USB returned an invalid length".into());
        }
        Ok(length as usize)
    }
}
impl Drop for Usb {
    fn drop(&mut self) {
        unsafe {
            hp_scanner_close(self.handle.as_ptr());
        }
    }
}

#[derive(Clone, Copy, Debug)]
pub struct Options {
    pub dpi: u32,
    pub color: bool,
}
impl Default for Options {
    fn default() -> Self {
        Self {
            dpi: 300,
            color: true,
        }
    }
}
impl Options {
    pub fn validate(self) -> Result<()> {
        if ![75, 100, 150, 200, 300, 600].contains(&self.dpi) {
            return Err("scan resolution must be 75, 100, 150, 200, 300 or 600 dpi".into());
        }
        Ok(())
    }
    fn configuration(self) -> [u8; 100] {
        let mut words = [0u32; 25];
        words[..8].copy_from_slice(&[0x15, 6, 6, self.dpi, 1, 1, 1, 1]);
        words[10] = 8;
        words[15] = if self.color { 2 } else { 6 };
        words[18] = 0x490; // A4: 297 mm, scanner coordinates in roughly 1/100 inch.
        words[19] = 825; // round(210 / 216 * 0x351), A4 width.
        words[22] = 0x491;
        words[23] = 0x352;
        words[24] = u32::from(self.color);
        let mut data = [0; 100];
        for (index, value) in words.iter().enumerate() {
            data[index * 4..index * 4 + 4].copy_from_slice(&value.to_be_bytes());
        }
        data
    }
}

fn packet(command: u32, size: u32) -> [u8; 32] {
    let mut result = [0; 32];
    result[..4].copy_from_slice(&MAGIC.to_be_bytes());
    result[4..8].copy_from_slice(&command.to_be_bytes());
    result[20..24].copy_from_slice(&size.to_be_bytes());
    result
}
fn value(bytes: &[u8], index: usize) -> u32 {
    u32::from_be_bytes(bytes[index * 4..index * 4 + 4].try_into().unwrap())
}
fn read_exact(usb: &mut impl Transport, mut bytes: &mut [u8]) -> Result<()> {
    let deadline = Instant::now() + Duration::from_secs(35);
    while !bytes.is_empty() {
        let length = bytes.len().min(512);
        let count = usb.read(&mut bytes[..length])?;
        if count > length {
            return Err("invalid USB packet length".into());
        }
        if count == 0 {
            if Instant::now() > deadline {
                return Err("scanner returned no data before timeout".into());
            }
            std::thread::sleep(Duration::from_millis(5));
        } else {
            bytes = &mut bytes[count..];
        }
    }
    Ok(())
}
fn header(usb: &mut impl Transport) -> Result<[u8; 32]> {
    let mut data = [0; 32];
    read_exact(usb, &mut data)?;
    if value(&data, 0) != MAGIC {
        return Err("invalid scanner packet magic".into());
    }
    if value(&data, 5) as usize > MAX_PACKET {
        return Err("scanner packet exceeds size limit".into());
    }
    Ok(data)
}
fn payload(usb: &mut impl Transport, length: usize) -> Result<Vec<u8>> {
    if length > MAX_PACKET {
        return Err("scanner payload exceeds size limit".into());
    }
    let mut bytes = vec![0; length];
    read_exact(usb, &mut bytes)?;
    Ok(bytes)
}
fn ack(usb: &mut impl Transport) -> Result<[u8; 32]> {
    let data = header(usb)?;
    let length = value(&data, 5) as usize;
    if length > 0 {
        payload(usb, length)?;
    }
    Ok(data)
}

pub struct Image {
    pub width: u32,
    pub height: u32,
    pub channels: u32,
    pub pixels: Vec<u8>,
}

impl Image {
    pub fn rotate_180(&mut self) {
        let channels = self.channels as usize;
        let count = self.pixels.len() / channels;
        for index in 0..count / 2 {
            for channel in 0..channels {
                self.pixels.swap(
                    index * channels + channel,
                    (count - 1 - index) * channels + channel,
                );
            }
        }
    }
}

struct Planes {
    width: u32,
    stride: u32,
    height: u32,
    color: bool,
    data: [Vec<u8>; 3],
}
impl Planes {
    fn new(height: u32, color: bool) -> Self {
        Self {
            width: 0,
            stride: 0,
            height,
            color,
            data: std::array::from_fn(|_| Vec::new()),
        }
    }
    fn add(&mut self, descriptor: &[u8], pixels: &[u8]) -> Result<()> {
        let (width, stride) = (value(descriptor, 4), value(descriptor, 5));
        if width == 0 || width > 5200 || stride < width || stride > width + 1024 {
            return Err(format!("invalid scanner dimensions {width}/{stride}").into());
        }
        if self.width != 0 && (width != self.width || stride != self.stride) {
            return Err("scanner dimensions changed during scan".into());
        }
        let plane = match (value(descriptor, 0), self.color) {
            (3, true) => 0,
            (4, true) => 1,
            (5, true) => 2,
            (6, false) => 0,
            _ => return Err("unexpected scanner color plane".into()),
        };
        self.width = width;
        self.stride = stride;
        let maximum = stride as usize * (self.height as usize + 64);
        if self.data[plane].len().saturating_add(pixels.len()) > maximum {
            return Err("scanner sent more image data than expected".into());
        }
        self.data[plane].extend_from_slice(pixels);
        Ok(())
    }
    fn image(self) -> Result<Image> {
        let channels = if self.color { 3 } else { 1 };
        if self.width == 0 {
            return Err("scanner returned no image data".into());
        }
        let expected = self.stride as usize * self.height as usize;
        for plane in &self.data[..channels] {
            if plane.len() < expected {
                return Err(format!(
                    "incomplete scan: {} of {expected} bytes in a color plane",
                    plane.len()
                )
                .into());
            }
        }
        let mut pixels = Vec::with_capacity(self.width as usize * self.height as usize * channels);
        for y in 0..self.height as usize {
            for x in 0..self.width as usize {
                for plane in &self.data[..channels] {
                    pixels.push(plane[y * self.stride as usize + x]);
                }
            }
        }
        Ok(Image {
            width: self.width,
            height: self.height,
            channels: channels as u32,
            pixels,
        })
    }
}

pub fn acquire(usb: &mut impl Transport, options: Options) -> Result<Image> {
    options.validate()?;
    usb.write(&packet(0x15, 0))?;
    usb.write(&packet(0, 0))?;
    let status = ack(usb)?;
    if value(&status, 4) != 0 {
        return Err(format!("scanner is not ready (status {})", value(&status, 4)).into());
    }
    usb.write(&packet(6, 0))?;
    ack(usb)?;
    usb.write(&packet(7, 100))?;
    usb.write(&options.configuration())?;
    ack(usb)?;
    eprintln!("Preparing scanner at {} dpi...", options.dpi);
    usb.write(&packet(2, 0))?;
    for _ in 0..4 {
        ack(usb)?;
    }
    let mut planes = Planes::new(0x490 * options.dpi / 100, options.color);
    let started = Instant::now();
    let mut last_progress = Instant::now();
    let mut cancel_logged = false;
    loop {
        if started.elapsed() > Duration::from_secs(600) {
            return Err("scan exceeded ten-minute safety timeout".into());
        }
        let data = header(usb)?;
        match value(&data, 1) {
            5 => {
                let length = value(&data, 5) as usize;
                if length < 24 {
                    return Err("scanner data packet is missing its descriptor".into());
                }
                let mut descriptor = [0; 24];
                read_exact(usb, &mut descriptor)?;
                let bytes = payload(usb, length - 24)?;
                if !CANCELED.load(Ordering::Relaxed) {
                    planes.add(&descriptor, &bytes)?;
                }
                if last_progress.elapsed() > Duration::from_secs(1) {
                    if planes.stride != 0 {
                        let rows = planes.data[0].len() / planes.stride as usize;
                        eprintln!(
                            "Scanning... {}%",
                            (rows * 100 / planes.height as usize).min(100)
                        );
                    }
                    last_progress = Instant::now();
                }
            }
            14 => {
                let count = value(&data, 5) as usize;
                if count > 0 {
                    payload(usb, count)?;
                }
                usb.write(&packet(3, 0))?;
                ack(usb)?;
                ack(usb)?;
                usb.write(&packet(1, 0))?;
                ack(usb)?;
                usb.write(&packet(0x15, 0))?;
                if CANCELED.load(Ordering::Relaxed) {
                    return Err("scan canceled".into());
                }
                return planes.image();
            }
            _ => {
                let count = value(&data, 5) as usize;
                if count > 0 {
                    payload(usb, count)?;
                }
            }
        }
        if CANCELED.load(Ordering::Relaxed) && !cancel_logged {
            eprintln!("Cancel requested; draining scanner data so the head can return home...");
            cancel_logged = true;
        }
    }
}

struct Temporary(PathBuf);
impl Drop for Temporary {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.0);
    }
}

pub fn save(image: &Image, dpi: u32, path: &Path) -> Result<()> {
    let extension = path
        .extension()
        .and_then(|v| v.to_str())
        .unwrap_or("")
        .to_ascii_lowercase();
    if extension != "png" && extension != "pdf" {
        return Err("output filename must end in .png or .pdf".into());
    }
    if path.exists() {
        return Err("output file already exists; choose a new filename".into());
    }
    if image.width == 0
        || image.height == 0
        || image.width > 16384
        || image.height > 16384
        || ![1, 3].contains(&image.channels)
        || dpi == 0
        || image.pixels.len()
            != image.width as usize * image.height as usize * image.channels as usize
    {
        return Err("invalid image buffer".into());
    }
    let temporary_path = path.with_extension(format!("m1005-{}-part", std::process::id()));
    // Reserve our temporary file without following or replacing an existing path.
    std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&temporary_path)?;
    let temporary = Temporary(temporary_path);
    let filename = CString::new(temporary.0.as_os_str().as_encoded_bytes())?;
    let result = unsafe {
        hp_scanner_save(
            image.pixels.as_ptr(),
            image.width,
            image.height,
            image.channels,
            dpi,
            filename.as_ptr(),
            i32::from(extension == "pdf"),
        )
    };
    if result != 0 {
        return Err("macOS could not save the scanned image".into());
    }
    // Same-directory hard link publishes the completed file atomically and refuses to overwrite.
    std::fs::hard_link(&temporary.0, path)?;
    Ok(())
}

pub fn scan(path: &Path, options: Options, rotate: bool) -> Result<()> {
    options.validate()?;
    if path.exists() {
        return Err("output file already exists; choose a new filename".into());
    }
    let extension = path
        .extension()
        .and_then(|v| v.to_str())
        .unwrap_or("")
        .to_ascii_lowercase();
    if !["png", "pdf"].contains(&extension.as_str()) {
        return Err("output filename must end in .png or .pdf".into());
    }
    CANCELED.store(false, Ordering::Relaxed);
    // SIGINT from the Scan app requests a clean drain rather than disconnecting mid-scan.
    unsafe {
        signal(2, interrupt);
    }
    let mut usb = Usb::open()?;
    let result = acquire(&mut usb, options);
    if result.is_err() {
        let _ = usb.write(&packet(0x15, 0));
    }
    let mut image = result?;
    if rotate {
        image.rotate_180();
    }
    save(&image, options.dpi, path)?;
    eprintln!("Scan saved: {} × {} pixels", image.width, image.height);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rotation_keeps_rgb_channels_together() {
        let mut image = Image {
            width: 2,
            height: 2,
            channels: 3,
            pixels: vec![1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
        };
        image.rotate_180();
        assert_eq!(image.pixels, [10, 11, 12, 7, 8, 9, 4, 5, 6, 1, 2, 3]);
    }
    #[test]
    fn output_never_overwrites_or_removes_existing_files() {
        let unique = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let folder =
            std::env::temp_dir().join(format!("m1005-save-{}-{unique}", std::process::id()));
        std::fs::create_dir(&folder).unwrap();
        let image = Image {
            width: 2,
            height: 1,
            channels: 1,
            pixels: vec![0, 255],
        };
        let output = folder.join("scan.png");
        std::fs::write(&output, b"keep existing output").unwrap();
        assert!(save(&image, 300, &output).is_err());
        assert_eq!(std::fs::read(&output).unwrap(), b"keep existing output");
        std::fs::remove_file(&output).unwrap();
        let temporary = output.with_extension(format!("m1005-{}-part", std::process::id()));
        std::fs::write(&temporary, b"keep existing temporary").unwrap();
        assert!(save(&image, 300, &output).is_err());
        assert_eq!(
            std::fs::read(&temporary).unwrap(),
            b"keep existing temporary"
        );
        std::fs::remove_file(&temporary).unwrap();
        save(&image, 300, &output).unwrap();
        assert!(
            std::fs::read(&output)
                .unwrap()
                .starts_with(b"\x89PNG\r\n\x1a\n")
        );
        std::fs::remove_dir_all(folder).unwrap();
    }
    #[test]
    fn scan_configuration_is_big_endian_and_a4_bounded() {
        let bytes = Options::default().configuration();
        assert_eq!(value(&bytes, 3), 300);
        assert_eq!(value(&bytes, 15), 2);
        assert_eq!(value(&bytes, 18), 1168);
        assert_eq!(value(&bytes, 19), 825);
        assert_eq!(value(&packet(7, 100), 5), 100);
        assert!(
            Options {
                dpi: 999,
                color: false
            }
            .validate()
            .is_err()
        );
    }
    #[test]
    fn reconstructs_planar_rgb_and_removes_row_padding() {
        let mut planes = Planes::new(2, true);
        for (layer, pixels) in [
            (3, [1, 2, 255, 3, 4, 255]),
            (4, [5, 6, 255, 7, 8, 255]),
            (5, [9, 10, 255, 11, 12, 255]),
        ] {
            let mut descriptor = [0; 24];
            for (index, number) in [(0, layer), (4, 2u32), (5, 3)] {
                descriptor[index * 4..index * 4 + 4].copy_from_slice(&number.to_be_bytes());
            }
            planes.add(&descriptor, &pixels).unwrap();
        }
        assert_eq!(
            planes.image().unwrap().pixels,
            [1, 5, 9, 2, 6, 10, 3, 7, 11, 4, 8, 12]
        );
    }
    #[test]
    fn rejects_invalid_or_incomplete_scan_data() {
        let mut planes = Planes::new(2, false);
        let mut descriptor = [0; 24];
        descriptor[..4].copy_from_slice(&6u32.to_be_bytes());
        descriptor[16..20].copy_from_slice(&2u32.to_be_bytes());
        descriptor[20..24].copy_from_slice(&1u32.to_be_bytes());
        assert!(planes.add(&descriptor, &[1]).is_err());
        descriptor[20..24].copy_from_slice(&2u32.to_be_bytes());
        planes.add(&descriptor, &[1, 2]).unwrap();
        assert!(planes.image().is_err());
    }
}
