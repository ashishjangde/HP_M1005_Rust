// XQX layout follows OpenPrinting foo2xqx by Rick Richardson (GPL-2.0-or-later).
use crate::{Result, bitmap::Bitmap, jbig};
use std::io::Write;

const END: u32 = 0x80000001;
const SENTINEL: u32 = 0xdeadbeef;
const MAX_CHUNK: usize = 65536;

#[derive(Clone, Copy)]
pub struct PageOptions {
    pub dpi: u32,
    pub paper: u32,
    pub copies: u32,
}

impl Default for PageOptions {
    fn default() -> Self {
        Self {
            dpi: 600,
            paper: 9,
            copies: 1,
        }
    }
}

fn word(out: &mut impl Write, value: u32) -> std::io::Result<()> {
    out.write_all(&value.to_be_bytes())
}
fn record(out: &mut impl Write, kind: u32, count: u32) -> std::io::Result<()> {
    word(out, kind)?;
    word(out, count)
}
fn item(out: &mut impl Write, kind: u32, value: u32) -> std::io::Result<()> {
    record(out, kind, 4)?;
    word(out, value)
}

pub struct Job<W: Write> {
    out: W,
    pages: u32,
}

impl<W: Write> Job<W> {
    pub fn new(mut out: W) -> Result<Self> {
        out.write_all(b"\x1b%-12345X@PJL JOB\n@PJL SET JAMRECOVERY=OFF\n@PJL SET DENSITY=3\n@PJL SET ECONOMODE=OFF\n@PJL SET RET=MEDIUM\n@PJL INFO STATUS\n@PJL USTATUS DEVICE = ON\n@PJL USTATUS JOB = ON\n@PJL USTATUS PAGE = ON\n@PJL USTATUS TIMED = 30\n@PJL SET JOBATTR=\"JobAttr4=19700101000000\"\0\x1b%-12345X,XQX")?;
        record(&mut out, 1, 7)?;
        for (kind, value) in [
            (0x80000000, 84),
            (0x10000005, 1),
            (0x10000001, 0),
            (0x10000002, 0),
            (0x10000000, 0),
            (0x10000003, 1),
            (END, SENTINEL),
        ] {
            item(&mut out, kind, value)?;
        }
        Ok(Self { out, pages: 0 })
    }

    pub fn page(&mut self, bitmap: &Bitmap, options: PageOptions) -> Result<()> {
        if options.dpi != 600 || !(1..=99).contains(&options.copies) {
            return Err("this version supports 600 dpi and 1–99 copies".into());
        }
        let encoded = jbig::encode(bitmap)?;
        record(&mut self.out, 3, 15)?;
        for (kind, value) in [
            (0x80000000, 180),
            (0x20000005, options.copies),
            (0x20000006, 7),
            (0x20000000, 1),
            (0x20000007, 1),
            (0x20000008, options.dpi),
            (0x20000009, options.dpi),
            (0x2000000d, (bitmap.stride * 8) as u32),
            (0x2000000e, bitmap.height),
            (0x2000000a, 1),
            (0x2000000f, bitmap.width),
            (0x20000010, bitmap.height),
            (0x20000011, 0),
            (0x20000001, options.paper),
            (END, SENTINEL),
        ] {
            item(&mut self.out, kind, value)?;
        }
        for (index, chunk) in encoded[20..].chunks(MAX_CHUNK).enumerate() {
            record(&mut self.out, 5, 4)?;
            item(&mut self.out, 0x80000000, if index == 0 { 64 } else { 48 })?;
            item(&mut self.out, 0x40000000, 0)?;
            if index == 0 {
                record(&mut self.out, 0x40000002, 20)?;
                self.out.write_all(&encoded[..20])?;
            } else {
                item(&mut self.out, 0x40000003, 1)?;
            }
            item(&mut self.out, END, SENTINEL)?;
            record(&mut self.out, 7, chunk.len() as u32)?;
            self.out.write_all(chunk)?;
            record(&mut self.out, 6, 0)?;
        }
        record(&mut self.out, 4, 0)?;
        self.pages += 1;
        Ok(())
    }

    pub fn finish(mut self) -> Result<W> {
        if self.pages == 0 {
            return Err("input contained no pages".into());
        }
        record(&mut self.out, 2, 0)?;
        self.out.write_all(b"\x1b%-12345X@PJL EOJ\n\x1b%-12345X")?;
        self.out.flush()?;
        Ok(self.out)
    }
}
