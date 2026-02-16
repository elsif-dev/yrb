use crate::utils::map_rhash_to_attrs;
use crate::ydiff::YDiff;
use crate::yvalue::YValue;
use crate::yxml_fragment::YXmlFragment;
use crate::{YTransaction, YXmlElement};
use magnus::block::Proc;
use magnus::value::Qnil;
use magnus::{Error, IntoValue, RArray, RHash, Ruby, Value};
use std::cell::RefCell;
use yrs::types::text::YChange;
use yrs::types::Delta;
use yrs::{Any, GetString, Observable, Text, Xml, XmlNode, XmlTextRef};

#[magnus::wrap(class = "Y::XMLText")]
pub(crate) struct YXmlText(pub(crate) RefCell<XmlTextRef>);

/// SAFETY: This is safe because we only access this data when the GVL is held.
unsafe impl Send for YXmlText {}

impl YXmlText {
    pub(crate) fn yxml_text_attributes(&self, transaction: &YTransaction) -> RHash {
        let ruby = unsafe { Ruby::get_unchecked() };
        let tx = transaction.transaction();
        let tx = tx.as_ref().unwrap();

        let hash = ruby.hash_new();
        for (k, v) in self.0.borrow().attributes(tx) {
            hash.aset(k, v).expect("cannot insert into hash");
        }
        hash
    }
    pub(crate) fn yxml_text_format(
        &self,
        transaction: &YTransaction,
        index: u32,
        length: u32,
        attrs: RHash,
    ) -> Result<(), Error> {
        let mut tx = transaction.transaction();
        let tx = tx.as_mut().unwrap();

        map_rhash_to_attrs(attrs).map(|a| self.0.borrow_mut().format(tx, index, length, a))
    }
    pub(crate) fn yxml_text_get_attribute(
        &self,
        transaction: &YTransaction,
        name: String,
    ) -> Option<String> {
        let tx = transaction.transaction();
        let tx = tx.as_ref().unwrap();

        self.0.borrow().get_attribute(tx, name.as_str())
    }
    pub(crate) fn yxml_text_insert(&self, transaction: &YTransaction, index: u32, content: String) {
        let mut tx = transaction.transaction();
        let tx = tx.as_mut().unwrap();

        self.0.borrow_mut().insert(tx, index, content.as_str())
    }
    pub(crate) fn yxml_text_insert_attribute(
        &self,
        transaction: &YTransaction,
        name: String,
        value: String,
    ) {
        let mut tx = transaction.transaction();
        let tx = tx.as_mut().unwrap();

        self.0.borrow_mut().insert_attribute(tx, name, value)
    }
    pub(crate) fn yxml_text_insert_embed_with_attributes(
        &self,
        transaction: &YTransaction,
        index: u32,
        content: Value,
        attrs: RHash,
    ) -> Result<(), Error> {
        let mut tx = transaction.transaction();
        let tx = tx.as_mut().unwrap();

        let yvalue = YValue::from(content);
        let avalue = Any::from(yvalue);

        map_rhash_to_attrs(attrs)
            .map(|a| {
                self.0
                    .borrow_mut()
                    .insert_embed_with_attributes(tx, index, avalue, a)
            })
            .map(|_| ())
    }
    pub(crate) fn yxml_text_insert_embed(
        &self,
        transaction: &YTransaction,
        index: u32,
        embed: Value,
    ) {
        let mut tx = transaction.transaction();
        let tx = tx.as_mut().unwrap();

        self.0
            .borrow_mut()
            .insert_embed(tx, index, Any::from(YValue::from(embed)));
    }
    pub(crate) fn yxml_text_insert_with_attributes(
        &self,
        transaction: &YTransaction,
        index: u32,
        content: String,
        attrs: RHash,
    ) -> Result<(), Error> {
        let mut tx = transaction.transaction();
        let tx = tx.as_mut().unwrap();

        map_rhash_to_attrs(attrs).map(|a| {
            self.0
                .borrow_mut()
                .insert_with_attributes(tx, index, content.as_str(), a);
        })
    }
    pub(crate) fn yxml_text_length(&self, transaction: &YTransaction) -> u32 {
        let tx = transaction.transaction();
        let tx = tx.as_ref().unwrap();

        self.0.borrow().len(tx)
    }
    pub(crate) fn yxml_text_next_sibling(&self, transaction: &YTransaction) -> Option<Value> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let tx = transaction.transaction();
        let tx = tx.as_ref().unwrap();

        self.0.borrow().siblings(tx).next().map(|item| match item {
            XmlNode::Element(el) => YXmlElement(RefCell::from(el)).into_value_with(&ruby),
            XmlNode::Fragment(fragment) => {
                YXmlFragment(RefCell::from(fragment)).into_value_with(&ruby)
            }
            XmlNode::Text(text) => YXmlText(RefCell::from(text)).into_value_with(&ruby),
        })
    }
    pub(crate) fn yxml_text_parent(&self) -> Option<Value> {
        let ruby = unsafe { Ruby::get_unchecked() };
        self.0.borrow().parent().map(|item| match item {
            XmlNode::Element(el) => YXmlElement(RefCell::from(el)).into_value_with(&ruby),
            XmlNode::Fragment(fragment) => {
                YXmlFragment(RefCell::from(fragment)).into_value_with(&ruby)
            }
            XmlNode::Text(text) => YXmlText(RefCell::from(text)).into_value_with(&ruby),
        })
    }
    pub(crate) fn yxml_text_prev_sibling(&self, transaction: &YTransaction) -> Option<Value> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let tx = transaction.transaction();
        let tx = tx.as_ref().unwrap();

        self.0
            .borrow()
            .siblings(tx)
            .next_back()
            .map(|item| match item {
                XmlNode::Element(el) => YXmlElement(RefCell::from(el)).into_value_with(&ruby),
                XmlNode::Fragment(fragment) => {
                    YXmlFragment(RefCell::from(fragment)).into_value_with(&ruby)
                }
                XmlNode::Text(text) => YXmlText(RefCell::from(text)).into_value_with(&ruby),
            })
    }
    pub(crate) fn yxml_text_push(&self, transaction: &YTransaction, content: String) {
        let mut tx = transaction.transaction();
        let tx = tx.as_mut().unwrap();

        self.0.borrow_mut().push(tx, content.as_str())
    }
    pub(crate) fn yxml_text_remove_range(
        &self,
        transaction: &YTransaction,
        index: u32,
        length: u32,
    ) {
        let mut tx = transaction.transaction();
        let tx = tx.as_mut().unwrap();

        self.0.borrow_mut().remove_range(tx, index, length)
    }
    pub(crate) fn yxml_text_to_s(&self, transaction: &YTransaction) -> String {
        let tx = transaction.transaction();
        let tx = tx.as_ref().unwrap();

        self.0.borrow().get_string(tx)
    }

    pub(crate) fn yxml_text_diff(&self, transaction: &YTransaction) -> RArray {
        let ruby = unsafe { Ruby::get_unchecked() };
        let tx = transaction.transaction();
        let tx = tx.as_ref().unwrap();

        let array = ruby.ary_new();
        for diff in self.0.borrow().diff(tx, YChange::identity).iter() {
            let yvalue = YValue::from(diff.insert.clone());
            let insert = yvalue.0.into_inner();
            let attributes = diff.attributes.as_ref().map_or_else(
                || None,
                |boxed_attrs| {
                    let attributes = ruby.hash_new();
                    for (key, value) in boxed_attrs.iter() {
                        let key = key.to_string();
                        let value = YValue::from(value.clone()).0.into_inner();
                        attributes.aset(key, value).expect("cannot add value");
                    }
                    Some(attributes)
                },
            );
            let ydiff = YDiff {
                ydiff_insert: insert,
                ydiff_attrs: attributes,
            };
            array
                .push(ydiff.into_value_with(&ruby))
                .expect("cannot push diff to array");
        }
        array
    }

    pub(crate) fn yxml_text_observe(&self, block: Proc) -> Result<u32, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let delta_insert = ruby.to_symbol("insert").to_static();
        let delta_retain = ruby.to_symbol("retain").to_static();
        let delta_delete = ruby.to_symbol("delete").to_static();
        let attributes = ruby.to_symbol("attributes").to_static();

        let subscription_id = self
            .0
            .borrow_mut()
            .observe(move |transaction, text_event| {
                let ruby = unsafe { Ruby::get_unchecked() };
                let delta = text_event.delta(transaction);
                for change in delta.iter() {
                    let payload = ruby.hash_new();
                    match change {
                        Delta::Inserted(value, attrs) => {
                            let yvalue = YValue::from(value.clone());
                            payload
                                .aset(delta_insert, yvalue.0.into_inner())
                                .expect("cannot set insert");
                            if let Some(a) = attrs {
                                let attrs_hash = ruby.hash_new();
                                for (key, val) in a.iter() {
                                    let yvalue = YValue::from(val.clone());
                                    attrs_hash
                                        .aset(key.to_string(), yvalue.0.into_inner())
                                        .expect("cannot add attr");
                                }
                                payload
                                    .aset(attributes, attrs_hash)
                                    .expect("cannot set attrs");
                            }
                        }
                        Delta::Retain(index, attrs) => {
                            let yvalue = YValue::from(*index);
                            payload
                                .aset(delta_retain, yvalue.0.into_inner())
                                .expect("cannot set retain");
                            if let Some(a) = attrs {
                                let attrs_hash = ruby.hash_new();
                                for (key, val) in a.iter() {
                                    let yvalue = YValue::from(val.clone());
                                    attrs_hash
                                        .aset(key.to_string(), yvalue.0.into_inner())
                                        .expect("cannot add attr");
                                }
                                payload
                                    .aset(attributes, attrs_hash)
                                    .expect("cannot set attrs");
                            }
                        }
                        Delta::Deleted(index) => {
                            let yvalue = YValue::from(*index);
                            payload
                                .aset(delta_delete, yvalue.0.into_inner())
                                .expect("cannot set delete");
                        }
                    }
                    let _ = block.call::<(RHash,), Qnil>((payload,));
                }
            })
            .into();

        Ok(subscription_id)
    }

    pub(crate) fn yxml_text_unobserve(&self, subscription_id: u32) {
        self.0.borrow_mut().unobserve(subscription_id);
    }
}

impl From<XmlTextRef> for YXmlText {
    fn from(v: XmlTextRef) -> Self {
        YXmlText(RefCell::from(v))
    }
}
