use crate::{Result, bitmap::Bitmap};
use std::ffi::c_void;

unsafe extern "C" {
    fn hp_jbig_encode(
        width: u32,
        height: u32,
        bitmap: *mut u8,
        output: unsafe extern "C" fn(*mut u8, usize, *mut c_void),
        context: *mut c_void,
    );
}

unsafe extern "C" fn collect(data: *mut u8, length: usize, context: *mut c_void) {
    // SAFETY: the C encoder calls synchronously with valid bytes and the supplied Vec pointer.
    let output = unsafe { &mut *context.cast::<Vec<u8>>() };
    output.extend_from_slice(unsafe { std::slice::from_raw_parts(data, length) });
}

pub fn encode(bitmap: &Bitmap) -> Result<Vec<u8>> {
    if bitmap.width == 0
        || bitmap.height == 0
        || bitmap.width > crate::bitmap::MAX_DIMENSION
        || bitmap.height > crate::bitmap::MAX_DIMENSION
    {
        return Err("invalid bitmap dimensions".into());
    }
    let stride = bitmap.width.div_ceil(128) as usize * 16;
    if bitmap.stride != stride || bitmap.pixels.len() != stride * bitmap.height as usize {
        return Err("invalid bitmap buffer layout".into());
    }
    let mut output = Vec::new();
    let mut pixels = bitmap.pixels.clone();
    // SAFETY: the bitmap owns exactly stride*height bytes; the aligned width matches its stride.
    unsafe {
        hp_jbig_encode(
            (bitmap.stride * 8) as u32,
            bitmap.height,
            pixels.as_mut_ptr(),
            collect,
            (&mut output as *mut Vec<u8>).cast(),
        );
    }
    if output.len() <= 20 {
        return Err("JBIG encoder returned an empty image".into());
    }
    Ok(output)
}

#[cfg(test)]
mod tests {
    use super::*;
    unsafe extern "C" {
        fn hp_jbig_decode(
            data: *mut u8,
            length: usize,
            output: *mut u8,
            capacity: usize,
            width: *mut u32,
            height: *mut u32,
        ) -> i32;
    }

    #[test]
    fn compressed_data_decodes_to_original_bitmap() {
        let mut bitmap = Bitmap::new(193, 257).unwrap();
        for y in 0..bitmap.height {
            for x in 0..bitmap.width {
                if (x * 13 + y * 7) % 19 < 8 {
                    bitmap.set_black(x, y);
                }
            }
        }
        let mut compressed = encode(&bitmap).unwrap();
        let mut decoded = vec![0; bitmap.pixels.len()];
        let (mut width, mut height) = (0, 0);
        let result = unsafe {
            hp_jbig_decode(
                compressed.as_mut_ptr(),
                compressed.len(),
                decoded.as_mut_ptr(),
                decoded.len(),
                &mut width,
                &mut height,
            )
        };
        assert_eq!(result, 0);
        assert_eq!((width, height), (256, 257));
        assert_eq!(decoded, bitmap.pixels);
    }
}
