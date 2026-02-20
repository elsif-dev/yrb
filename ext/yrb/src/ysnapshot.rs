use magnus::Error;
use yrs::updates::decoder::Decode;
use yrs::updates::encoder::Encode;
use yrs::Snapshot;

#[magnus::wrap(class = "Y::Snapshot")]
pub(crate) struct YSnapshot(pub(crate) Snapshot);

unsafe impl Send for YSnapshot {}

impl YSnapshot {
    pub(crate) fn ysnapshot_decode_v1(data: Vec<u8>) -> Result<Self, Error> {
        let ruby = magnus::Ruby::get().unwrap();
        Snapshot::decode_v1(&data)
            .map(|s| YSnapshot(s))
            .map_err(|e| {
                Error::new(
                    ruby.exception_runtime_error(),
                    format!("cannot decode snapshot: {:?}", e),
                )
            })
    }

    pub(crate) fn ysnapshot_encode_v1(&self) -> Vec<u8> {
        self.0.encode_v1()
    }
}

impl From<Snapshot> for YSnapshot {
    fn from(s: Snapshot) -> Self {
        YSnapshot(s)
    }
}
