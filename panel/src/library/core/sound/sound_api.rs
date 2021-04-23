extern crate libpulse_binding as pulse;

use std::cell::RefCell;
use std::ops::Deref;
use std::rc::Rc;

use super::errors::{
    PulseCtlError,
    PulseCtlErrorType::{ConnectError, OperationError},
};
use pulse::{
    context::{introspect, Context, FlagSet},
    mainloop::standard::{IterateResult, Mainloop},
    operation::{Operation, State},
    proplist::Proplist,
};
pub struct Handler {
    pub mainloop: Rc<RefCell<Mainloop>>,
    pub context: Rc<RefCell<Context>>,
    pub introspect: introspect::Introspector,
}
impl Default for Handler {
    fn default() -> Self {
        let mut proplist = Proplist::new().unwrap();
        proplist
            .set_str(pulse::proplist::properties::APPLICATION_NAME, "SystemSound")
            .unwrap();

        let mainlp = Rc::new(RefCell::new(
            Mainloop::new().expect("Failed to create mainloop"),
        ));

        let con = Rc::new(RefCell::new(
            Context::new_with_proplist(mainlp.borrow().deref(), "MainConn", &proplist)
                .expect("Failed to create new context"),
        ));

        con.borrow_mut()
            .connect(None, FlagSet::NOFLAGS, None)
            .expect("Failed to connect context");
        let intro = con.borrow_mut().introspect();
        Self {
            mainloop: mainlp,
            context: con,
            introspect: intro,
        }
    }
}

impl Handler {
    pub fn connect(name: &str) -> Result<Handler, PulseCtlError> {
        let mut proplist = Proplist::new().unwrap();
        proplist
            .set_str(pulse::proplist::properties::APPLICATION_NAME, name)
            .unwrap();

        let mainloop = Rc::new(RefCell::new(
            Mainloop::new().expect("Failed to create mainloop"),
        ));

        let context = Rc::new(RefCell::new(
            Context::new_with_proplist(mainloop.borrow().deref(), "MainConn", &proplist)
                .expect("Failed to create new context"),
        ));

        context
            .borrow_mut()
            .connect(None, FlagSet::NOFLAGS, None)
            .expect("Failed to connect context");

        loop {
            match mainloop.borrow_mut().iterate(false) {
                IterateResult::Err(e) => {
                    eprintln!("iterate state was not success, quitting...");
                    return Err(e.into());
                }
                IterateResult::Success(_) => {}
                IterateResult::Quit(_) => {
                    eprintln!("iterate state was not success, quitting...");
                    return Err(PulseCtlError::new(
                        ConnectError,
                        "Iterate state quit without an error",
                    ));
                }
            }

            match context.borrow().get_state() {
                pulse::context::State::Ready => break,
                pulse::context::State::Failed | pulse::context::State::Terminated => {
                    eprintln!("context state failed/terminated, quitting...");
                    return Err(PulseCtlError::new(
                        ConnectError,
                        "Context state failed/terminated without an error",
                    ));
                }
                _ => {}
            }
        }

        let introspect = context.borrow_mut().introspect();
        Ok(Handler {
            mainloop,
            context,
            introspect,
        })
    }
    // loop until the passed operation is completed
    pub fn wait_for_operation<G: ?Sized>(&mut self, op: Operation<G>) -> Result<(), PulseCtlError> {
        loop {
            match self.mainloop.borrow_mut().iterate(false) {
                IterateResult::Err(e) => return Err(e.into()),
                IterateResult::Success(_) => {}
                IterateResult::Quit(_) => {
                    return Err(PulseCtlError::new(
                        OperationError,
                        "Iterate state quit without an error",
                    ));
                }
            }
            match op.get_state() {
                State::Done => {
                    break;
                }
                State::Running => {}
                State::Cancelled => {
                    return Err(PulseCtlError::new(
                        OperationError,
                        "Operation cancelled without an error",
                    ));
                }
            }
        }
        Ok(())
    }
}

impl Drop for Handler {
    fn drop(&mut self) {
        self.context.borrow_mut().disconnect();
        self.mainloop.borrow_mut().quit(pulse::def::Retval(0));
    }
}
