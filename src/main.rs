use m1005::{
    Result,
    bitmap::{Bitmap, read_pbm, write_pbm},
    raster::{Raster, paper_code},
    xqx::{Job, PageOptions},
};
use std::{
    fs::File,
    io::{BufReader, BufWriter, Write},
    os::fd::AsRawFd,
};

fn filter(args: &[String]) -> Result<()> {
    // Standard CUPS ABI: executable job-id user title copies options [raster-file].
    if args.len() != 6 && args.len() != 7 {
        return Err("invalid CUPS filter arguments".into());
    }
    let copies: u32 = args[4].parse()?;
    if !(1..=99).contains(&copies) {
        return Err("copies must be between 1 and 99".into());
    }
    // CUPS supplies an inherited pipe on fd 0. Reopening /dev/stdin is forbidden
    // by the macOS print sandbox, so use that descriptor directly.
    let input = args.get(6).map(File::open).transpose()?;
    let descriptor = input.as_ref().map(AsRawFd::as_raw_fd).unwrap_or(0);
    let mut raster = Raster::open(descriptor)?;
    let mut job = Job::new(BufWriter::new(std::io::stdout().lock()))?;
    let mut page_number = 0;
    while let Some((bitmap, info)) = raster.next_page()? {
        page_number += 1;
        eprintln!(
            "INFO: M1005 Rust: page {page_number}, {}x{} pixels at 600 dpi",
            bitmap.width, bitmap.height
        );
        job.page(
            &bitmap,
            PageOptions {
                copies,
                paper: paper_code(info.page_width, info.page_height)?,
                dpi: 600,
            },
        )?;
        eprintln!("PAGE: {page_number} {copies}");
    }
    job.finish()?;
    Ok(())
}

fn test_page() -> Result<Bitmap> {
    let mut bitmap = Bitmap::new(4960, 7016)?;
    // A4 at 600 dpi; generous margins, sparse calibration marks and readable bitmap text.
    for y in 300..6700 {
        for x in 300..4660 {
            if !(310..4650).contains(&x) || !(310..6690).contains(&y) {
                bitmap.set_black(x, y);
            }
        }
    }
    text(&mut bitmap, "RUST M1005 TEST", 550, 600, 28);
    text(&mut bitmap, "NATIVE ARM64", 550, 1000, 22);
    text(&mut bitmap, "600 DPI A4 USB", 550, 1400, 22);
    for band in 0..8 {
        for y in 2200..3000 {
            for x in (550 + band * 480)..(950 + band * 480) {
                if ((x + y) % 8) <= band {
                    bitmap.set_black(x, y);
                }
            }
        }
    }
    for y in 3600..4200 {
        for x in 550..4400 {
            if ((x - 550) / 40 + (y - 3600) / 40) % 2 == 0 {
                bitmap.set_black(x, y);
            }
        }
    }
    text(&mut bitmap, "PRINT OK", 550, 4900, 32);
    Ok(bitmap)
}

fn text(bitmap: &mut Bitmap, text: &str, x: u32, y: u32, scale: u32) {
    for (index, character) in text.chars().enumerate() {
        let glyph: [u8; 7] = match character {
            'A' => [14, 17, 17, 31, 17, 17, 17],
            'D' => [30, 17, 17, 17, 17, 17, 30],
            'E' => [31, 16, 16, 30, 16, 16, 31],
            'I' => [31, 4, 4, 4, 4, 4, 31],
            'K' => [17, 18, 20, 24, 20, 18, 17],
            'M' => [17, 27, 21, 21, 17, 17, 17],
            'N' => [17, 25, 21, 19, 17, 17, 17],
            'O' => [14, 17, 17, 17, 17, 17, 14],
            'P' => [30, 17, 17, 30, 16, 16, 16],
            'R' => [30, 17, 17, 30, 20, 18, 17],
            'S' => [15, 16, 16, 14, 1, 1, 30],
            'T' => [31, 4, 4, 4, 4, 4, 4],
            'U' => [17, 17, 17, 17, 17, 17, 14],
            'V' => [17, 17, 17, 17, 17, 10, 4],
            'B' => [30, 17, 17, 30, 17, 17, 30],
            '0' => [14, 17, 19, 21, 25, 17, 14],
            '1' => [4, 12, 4, 4, 4, 4, 14],
            '4' => [2, 6, 10, 18, 31, 2, 2],
            '5' => [31, 16, 16, 30, 1, 1, 30],
            '6' => [14, 16, 16, 30, 17, 17, 14],
            _ => [0; 7],
        };
        for (gy, row) in glyph.iter().enumerate() {
            for gx in 0..5 {
                if row & (16 >> gx) != 0 {
                    for dy in 0..scale {
                        for dx in 0..scale {
                            bitmap.set_black(
                                x + index as u32 * 6 * scale + gx * scale + dx,
                                y + gy as u32 * scale + dy,
                            );
                        }
                    }
                }
            }
        }
    }
}

fn run() -> Result<()> {
    let args: Vec<String> = std::env::args().collect();
    match args.get(1).map(String::as_str) {
        Some("scan-probe") if args.len() == 2 => {
            let _usb = m1005::scanner::Usb::open()?;
            println!("HP LaserJet M1005 scanner interface is available.");
        }
        Some("scan") if (3..=6).contains(&args.len()) => {
            let dpi = args.get(3).map(|v| v.parse()).transpose()?.unwrap_or(300);
            let color = match args.get(4).map(String::as_str).unwrap_or("color") {
                "color" => true,
                "gray" => false,
                _ => return Err("scan mode must be color or gray".into()),
            };
            let rotate = match args.get(5).map(String::as_str).unwrap_or("0") {
                "0" => false,
                "180" => true,
                _ => return Err("rotation must be 0 or 180 degrees".into()),
            };
            m1005::scanner::scan(
                std::path::Path::new(&args[2]),
                m1005::scanner::Options { dpi, color },
                rotate,
            )?;
        }
        Some("encode") if args.len() == 4 || args.len() == 5 => {
            let paper = match args.get(4).map(String::as_str).unwrap_or("A4") {
                "A4" => 9,
                "Letter" => 1,
                "Legal" => 5,
                "A5" => 11,
                _ => return Err("paper must be A4, Letter, Legal or A5".into()),
            };
            let mut input = BufReader::new(File::open(&args[2])?);
            let output = BufWriter::new(File::create(&args[3])?);
            let mut job = Job::new(output)?;
            while let Some(bitmap) = read_pbm(&mut input)? {
                job.page(
                    &bitmap,
                    PageOptions {
                        paper,
                        ..PageOptions::default()
                    },
                )?;
            }
            job.finish()?;
        }
        Some("test-page") if args.len() == 3 => {
            let mut out = BufWriter::new(File::create(&args[2])?);
            write_pbm(&test_page()?, &mut out)?;
            out.flush()?;
        }
        Some("filter") => {
            let filter_args: Vec<String> = std::iter::once(args[0].clone())
                .chain(args[2..].iter().cloned())
                .collect();
            return filter(&filter_args);
        }
        Some(job_id) if job_id.parse::<u32>().is_ok() => return filter(&args),
        _ => {
            eprintln!(
                "M1005 native Rust driver\n  m1005 scan output.png|output.pdf [dpi] [color|gray]\n  m1005 scan-probe\n  m1005 test-page output.pbm\n  m1005 encode input.pbm output.xqx [A4|Letter|Legal|A5]\n  m1005 filter job-id user title copies options [raster-file]"
            );
            return Err("provide a command or CUPS filter arguments".into());
        }
    }
    Ok(())
}

fn main() {
    if let Err(error) = run() {
        eprintln!("ERROR: M1005 Rust: {error}");
        std::process::exit(1);
    }
}
