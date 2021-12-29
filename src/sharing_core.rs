use crossbeam::channel::Sender;
use std::ffi::c_void;
use std::os::raw::{c_int, c_uchar};
use std::ptr;

pub struct SharingCorePointer(pub *const c_void);
unsafe impl Send for SharingCorePointer {}

pub extern "C" fn callback(
    target: *mut Sender<Vec<u8>>,
    packet_pointer: *const c_uchar,
    packet_length: c_int,
) {
    let packet_length = packet_length as usize;

    let mut packet: Vec<u8> = Vec::with_capacity(packet_length);

    unsafe {
        ptr::copy(packet_pointer, packet.as_mut_ptr(), packet_length);
        packet.set_len(packet_length);
        (*target).send(packet).expect("send callback data failed");
    }
}

extern "C" {
    pub fn SharingCoreInit(
        extra: *mut Sender<Vec<u8>>,
        cb: extern "C" fn(*mut Sender<Vec<u8>>, *const c_uchar, c_int),
        width: u32,
        height: u32,
        fps: u32,
    ) -> *const c_void;
    pub fn SharingCoreBeginScreenCapture(pointer: *const c_void);
    pub fn SharingCoreStopScreenCapture(pointer: *const c_void);
    pub fn SharingCoreDeallocate(pointer: *const c_void);
}
