use std::cell::RefCell;
use std::sync::{Arc, Mutex};
use magnus::Error;
use yrs::undo::{self, Options, EventKind};

use crate::ydoc::YDoc;
use crate::yxml_fragment::YXmlFragment;

#[derive(Clone, Default)]
struct StackMeta {
    meta: Vec<u8>,
}

struct ObserverState {
    undo_metas: Vec<StackMeta>,
    redo_metas: Vec<StackMeta>,
}

#[magnus::wrap(class = "Y::UndoManager")]
pub(crate) struct YUndoManager {
    manager: RefCell<undo::UndoManager<Vec<u8>>>,
    state: Arc<Mutex<ObserverState>>,
    _sub_added: RefCell<Option<undo::UndoEventSubscription<Vec<u8>>>>,
    _sub_popped: RefCell<Option<undo::UndoEventSubscription<Vec<u8>>>>,
}

unsafe impl Send for YUndoManager {}

impl YUndoManager {
    pub(crate) fn yundo_manager_new(doc: &YDoc, fragment: &YXmlFragment) -> Result<Self, Error> {
        let doc_ref = doc.0.borrow();
        let frag_ref = fragment.0.borrow();

        let options = Options {
            capture_timeout_millis: 0,
            ..Options::default()
        };

        let manager: undo::UndoManager<Vec<u8>> = undo::UndoManager::with_options(&*doc_ref, &*frag_ref, options);

        let state = Arc::new(Mutex::new(ObserverState {
            undo_metas: Vec::new(),
            redo_metas: Vec::new(),
        }));

        let state_added = Arc::clone(&state);
        let sub_added = manager.observe_item_added(move |_txn, event| {
            let mut s = state_added.lock().unwrap();
            // EventKind::Redo = normal forward edit added to undo stack
            // EventKind::Undo = undo operation created item on redo stack
            match event.kind() {
                EventKind::Redo => {
                    // Forward edit: new item on undo stack, clear redo stack
                    s.redo_metas.clear();
                    s.undo_metas.push(StackMeta {
                        meta: event.item.meta.clone(),
                    });
                }
                EventKind::Undo => {
                    // Undo operation: new item on redo stack
                    s.redo_metas.push(StackMeta {
                        meta: event.item.meta.clone(),
                    });
                }
            }
        });

        let state_popped = Arc::clone(&state);
        let sub_popped = manager.observe_item_popped(move |_txn, event| {
            let mut s = state_popped.lock().unwrap();
            // EventKind::Undo = item popped from undo stack (undo called)
            // EventKind::Redo = item popped from redo stack (redo called)
            match event.kind() {
                EventKind::Undo => {
                    s.undo_metas.pop();
                }
                EventKind::Redo => {
                    s.redo_metas.pop();
                }
            }
        });

        Ok(YUndoManager {
            manager: RefCell::new(manager),
            state,
            _sub_added: RefCell::new(Some(sub_added)),
            _sub_popped: RefCell::new(Some(sub_popped)),
        })
    }

    pub(crate) fn yundo_manager_include_origin(&self, origin: Vec<u8>) {
        self.manager.borrow_mut().include_origin(origin.as_slice());
    }

    pub(crate) fn yundo_manager_undo(&self) -> Result<bool, Error> {
        let ruby = magnus::Ruby::get().unwrap();
        self.manager.borrow_mut().undo()
            .map_err(|e| Error::new(ruby.exception_runtime_error(), format!("undo failed: {:?}", e)))
    }

    pub(crate) fn yundo_manager_redo(&self) -> Result<bool, Error> {
        let ruby = magnus::Ruby::get().unwrap();
        self.manager.borrow_mut().redo()
            .map_err(|e| Error::new(ruby.exception_runtime_error(), format!("redo failed: {:?}", e)))
    }

    pub(crate) fn yundo_manager_can_undo(&self) -> bool {
        self.manager.borrow().can_undo()
    }

    pub(crate) fn yundo_manager_can_redo(&self) -> bool {
        self.manager.borrow().can_redo()
    }

    pub(crate) fn yundo_manager_reset(&self) {
        self.manager.borrow_mut().reset();
    }

    pub(crate) fn yundo_manager_clear(&self) -> Result<(), Error> {
        let ruby = magnus::Ruby::get().unwrap();
        self.manager.borrow_mut().clear()
            .map_err(|e| Error::new(ruby.exception_runtime_error(), format!("clear failed: {:?}", e)))?;
        let mut s = self.state.lock().unwrap();
        s.undo_metas.clear();
        s.redo_metas.clear();
        Ok(())
    }

    pub(crate) fn yundo_manager_undo_stack_length(&self) -> usize {
        self.state.lock().unwrap().undo_metas.len()
    }

    pub(crate) fn yundo_manager_redo_stack_length(&self) -> usize {
        self.state.lock().unwrap().redo_metas.len()
    }

    pub(crate) fn yundo_manager_undo_stack_metas(&self) -> Vec<Vec<u8>> {
        self.state.lock().unwrap().undo_metas.iter().map(|m| m.meta.clone()).collect()
    }

    pub(crate) fn yundo_manager_redo_stack_metas(&self) -> Vec<Vec<u8>> {
        self.state.lock().unwrap().redo_metas.iter().map(|m| m.meta.clone()).collect()
    }

    pub(crate) fn yundo_manager_set_last_undo_meta(&self, meta: Vec<u8>) {
        let mut s = self.state.lock().unwrap();
        if let Some(last) = s.undo_metas.last_mut() {
            last.meta = meta;
        }
    }
}
