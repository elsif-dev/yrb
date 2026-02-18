use magnus::{Error, Ruby};
use yrs::updates::decoder::Decode;
use yrs::updates::encoder::Encode;
use yrs::Snapshot;

#[magnus::wrap(class = "Y::Snapshot")]
pub(crate) struct YSnapshot(pub(crate) Snapshot);

unsafe impl Send for YSnapshot {}

impl YSnapshot {
    pub(crate) fn ysnapshot_encode_v1(&self) -> Vec<u8> {
        self.0.encode_v1()
    }

    pub(crate) fn ysnapshot_encode_v2(&self) -> Vec<u8> {
        self.0.encode_v2()
    }

    pub(crate) fn ysnapshot_decode_v1(encoded: Vec<u8>) -> Result<Self, Error> {
        let ruby = Ruby::get().unwrap();
        Snapshot::decode_v1(encoded.as_slice())
            .map(YSnapshot)
            .map_err(|e| {
                Error::new(
                    ruby.exception_runtime_error(),
                    format!("cannot decode v1 snapshot: {}", e),
                )
            })
    }

    pub(crate) fn ysnapshot_decode_v2(encoded: Vec<u8>) -> Result<Self, Error> {
        let ruby = Ruby::get().unwrap();
        Snapshot::decode_v2(encoded.as_slice())
            .map(YSnapshot)
            .map_err(|e| {
                Error::new(
                    ruby.exception_runtime_error(),
                    format!("cannot decode v2 snapshot: {}", e),
                )
            })
    }

    pub(crate) fn ysnapshot_equal(&self, other: &YSnapshot) -> bool {
        self.0 == other.0
    }
}

impl From<Snapshot> for YSnapshot {
    fn from(snapshot: Snapshot) -> Self {
        YSnapshot(snapshot)
    }
}
