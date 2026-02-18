use crate::yarray::YArray;
use crate::ymap::YMap;
use crate::ysnapshot::YSnapshot;
use crate::ytext::YText;
use crate::yxml_element::YXmlElement;
use crate::yxml_fragment::YXmlFragment;
use crate::yxml_text::YXmlText;
use crate::YTransaction;
use magnus::block::Proc;
use magnus::{Error, Integer, RArray, RHash, Ruby, TryConvert, Value};
use std::borrow::Borrow;
use std::cell::RefCell;
use yrs::updates::decoder::Decode;
use yrs::updates::encoder::{Encoder, EncoderV1, EncoderV2};
use yrs::{Doc, OffsetKind, Options, ReadTxn, StateVector, SubscriptionId, Transact};

#[magnus::wrap(class = "Y::Doc")]
pub(crate) struct YDoc(pub(crate) RefCell<Doc>);

unsafe impl Send for YDoc {}

impl YDoc {
    pub(crate) fn ydoc_new(args: &[Value]) -> Self {
        let mut options = Options::default();
        options.offset_kind = OffsetKind::Utf16;

        let ruby = Ruby::get().unwrap();
        for arg in args {
            if let Some(int) = Integer::from_value(*arg) {
                options.client_id = int.to_u64().unwrap();
            } else if let Some(hash) = RHash::from_value(*arg) {
                let gc_sym = ruby.to_symbol("gc");
                if let Some(gc_val) = hash.get(gc_sym) {
                    if let Ok(gc_bool) = bool::try_convert(gc_val) {
                        options.skip_gc = !gc_bool;
                    }
                }
            }
        }

        let doc = Doc::with_options(options);
        Self(RefCell::new(doc))
    }

    pub(crate) fn ydoc_encode_diff_v1(
        &self,
        transaction: &YTransaction,
        state_vector: Vec<u8>,
    ) -> Result<Vec<u8>, Error> {
        let ruby = Ruby::get().unwrap();
        let mut tx = transaction.transaction();
        let tx = tx.as_mut().unwrap();

        StateVector::decode_v1(state_vector.borrow())
            .map(|sv| tx.encode_diff_v1(&sv))
            .map_err(|_e| Error::new(ruby.exception_runtime_error(), "cannot encode diff"))
    }

    pub(crate) fn ydoc_encode_diff_v2(
        &self,
        transaction: &YTransaction,
        state_vector: Vec<u8>,
    ) -> Result<Vec<u8>, Error> {
        let ruby = Ruby::get().unwrap();
        let mut tx = transaction.transaction();
        let tx = tx.as_mut().unwrap();
        let mut encoder = EncoderV2::new();

        StateVector::decode_v2(state_vector.borrow())
            .map(|sv| tx.encode_diff(&sv, &mut encoder))
            .map(|_| encoder.to_vec())
            .map_err(|_e| Error::new(ruby.exception_runtime_error(), "cannot encode diff"))
    }

    pub(crate) fn ydoc_get_or_insert_array(&self, name: String) -> YArray {
        let array_ref = self.0.borrow().get_or_insert_array(name.as_str());
        YArray::from(array_ref)
    }

    pub(crate) fn ydoc_get_or_insert_map(&self, name: String) -> YMap {
        let map_ref = self.0.borrow().get_or_insert_map(name.as_str());
        YMap::from(map_ref)
    }

    pub(crate) fn ydoc_get_or_insert_text(&self, name: String) -> YText {
        let text_ref = self.0.borrow().get_or_insert_text(name.as_str());
        YText::from(text_ref)
    }

    pub(crate) fn ydoc_get_or_insert_xml_element(&self, name: String) -> YXmlElement {
        let xml_element_ref = self.0.borrow_mut().get_or_insert_xml_element(name.as_str());
        YXmlElement::from(xml_element_ref) // ::into() maps to YXmlFragment instead of YXmlElement :-(
    }

    pub(crate) fn ydoc_get_or_insert_xml_fragment(&self, name: String) -> YXmlFragment {
        let xml_fragment_ref = self.0.borrow().get_or_insert_xml_fragment(name.as_str());
        YXmlFragment::from(xml_fragment_ref)
    }

    pub(crate) fn ydoc_get_or_insert_xml_text(&self, name: String) -> YXmlText {
        let xml_text_ref = self.0.borrow().get_or_insert_xml_text(name.as_str());
        YXmlText::from(xml_text_ref)
    }

    pub(crate) fn ydoc_transact(&self) -> YTransaction {
        let doc = self.0.borrow();
        let transaction = doc.transact_mut();
        YTransaction::from(transaction)
    }

    pub(crate) fn ydoc_observe_update(&self, block: Proc) -> Result<SubscriptionId, Error> {
        let ruby = Ruby::get().unwrap();
        self.0
            .borrow()
            .observe_update_v1(move |_tx, update_event| {
                let ruby = unsafe { Ruby::get_unchecked() };
                let update = update_event.update.to_vec();
                let update = ruby.ary_from_vec(update);

                let args: (RArray,) = (update,);
                block
                    .call::<(RArray,), Value>(args)
                    .expect("cannot call update block");
            })
            .map(|v| v.into())
            .map_err(|err| Error::new(ruby.exception_runtime_error(), err.to_string()))
    }

    pub(crate) fn ydoc_snapshot(&self) -> YSnapshot {
        let doc = self.0.borrow();
        let txn = doc.transact();
        let snapshot = txn.snapshot();
        YSnapshot::from(snapshot)
    }

    pub(crate) fn ydoc_encode_state_from_snapshot_v1(
        &self,
        snapshot: &YSnapshot,
    ) -> Result<Vec<u8>, Error> {
        let ruby = Ruby::get().unwrap();
        let doc = self.0.borrow();
        let txn = doc.transact();
        let mut encoder = EncoderV1::new();
        txn.encode_state_from_snapshot(&snapshot.0, &mut encoder)
            .map(|_| encoder.to_vec())
            .map_err(|_e| {
                Error::new(
                    ruby.exception_runtime_error(),
                    "cannot encode state from snapshot: document was created with \
                     garbage collection enabled. Use Y::Doc.new(gc: false) to \
                     enable snapshot support.",
                )
            })
    }

    pub(crate) fn ydoc_encode_state_from_snapshot_v2(
        &self,
        snapshot: &YSnapshot,
    ) -> Result<Vec<u8>, Error> {
        let ruby = Ruby::get().unwrap();
        let doc = self.0.borrow();
        let txn = doc.transact();
        let mut encoder = EncoderV2::new();
        txn.encode_state_from_snapshot(&snapshot.0, &mut encoder)
            .map(|_| encoder.to_vec())
            .map_err(|_e| {
                Error::new(
                    ruby.exception_runtime_error(),
                    "cannot encode state from snapshot: document was created with \
                     garbage collection enabled. Use Y::Doc.new(gc: false) to \
                     enable snapshot support.",
                )
            })
    }
}
