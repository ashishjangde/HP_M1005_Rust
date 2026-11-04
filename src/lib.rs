pub mod bitmap;
pub mod jbig;
pub mod raster;
pub mod scanner;
pub mod xqx;

pub type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
