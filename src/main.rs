use crate::sharing_core::SharingCorePointer;
use tokio::io::AsyncWriteExt;
use tokio::net::TcpListener;

pub mod sharing_core;

#[tokio::main]
async fn main() -> std::io::Result<()> {
    let listener = TcpListener::bind("127.0.0.1:18999").await?;

    loop {
        match listener.accept().await {
            Ok((mut socket, _)) => {
                tokio::spawn(async move {
                    let (sender, receiver) = crossbeam::channel::unbounded();
                    let mut p_sender = Box::new(sender);
                    let sharing_core_ptr: SharingCorePointer;

                    unsafe {
                        let ptr = crate::sharing_core::SharingCoreInit(
                            &mut *p_sender,
                            crate::sharing_core::callback,
                            1920,
                            1080,
                            60,
                        );
                        if ptr.is_null() {
                            println!("init sharing core failed");
                            return;
                        }

                        sharing_core_ptr = SharingCorePointer(ptr);
                    }

                    unsafe {
                        crate::sharing_core::SharingCoreBeginScreenCapture(sharing_core_ptr.0);
                    }

                    loop {
                        match receiver.recv() {
                            Ok(pkt) => {
                                if let Err(e) = socket.write_all(&pkt).await {
                                    eprintln!("failed to write to socket; err = {:?}", e);
                                    break;
                                }
                            }
                            Err(e) => {
                                eprintln!("{:?}", e);
                                break;
                            }
                        }
                    }

                    unsafe {
                        crate::sharing_core::SharingCoreStopScreenCapture(sharing_core_ptr.0);
                        crate::sharing_core::SharingCoreDeallocate(sharing_core_ptr.0);
                    }
                });
            }
            Err(e) => println!("{:?}", e),
        }
    }
}
