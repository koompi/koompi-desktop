# J46: the three bugs the Rust service-layer port found

Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first.
Source: `~/.config/koompi/TODO.md`, section "Found by the Rust service layer port" (read it; it is the evidence).
The founder asked for these on 2026-10-09.

## State the lead found (dev at the base commit)

- Battery: likely already fixed. `services/Battery.qml` reads `isPluggedIn` from `ShellServices.power?.plugged_in`, not from the charge state. Confirm where `plugged_in` comes from in `shell-services/` (UPower's `OnBattery` on the manager, or not), and that nothing else in the shell still derives plugged-in from the charge state (`git grep` for `isCharging ||`, `PendingCharge`, `fully-charged`). If it is fixed, say so with file:line and add the smallest check that keeps it fixed, if none exists.
- Suspend: `services/SessionWarnings.qml` no longer greps `CanSuspend`; it greps `CanHibernate` for `yes|challenge`. The Rust session crate (`shell-services/session/src/capability.rs`, `action.rs`) already models logind's answers including `inhibited`. Find every place in the shell that asks logind a `Can*` question (QML and scripts), and make each one read logind's answer correctly: `inhibited` means "can, once the inhibitor goes", not "cannot". Prefer the shell-services value if `ShellServices` publishes it; do not add a second reader. Test: a stub logind on the test's private bus answering `inhibited` reads as possible.
- Media: `services/MprisController.qml:131-150` and below, the `activePlayerStale` workaround (3 s timer, `playerctl` fork) for a `plasma-browser-integration` freeze that was never reproduced. Do not delete it on that alone. Try to reproduce it: a private session bus, a stub MPRIS player that behaves as the TODO describes the real one (ending goes `Paused` with `Position` pinned at the length; tearing the element out drops the bus name). Report whether the shell without the workaround shows a phantom player in each case, with evidence. The lead decides removal from that; write the removal as a separate last commit only if both cases are clean, so it can be dropped.

## Files owned

`services/Battery.qml`, `services/SessionWarnings.qml`, `services/MprisController.qml`, any other shell file that asks logind a `Can*` question (name it), their tests in `tests/`, and docs that describe them.

## Acceptance

- Each behaviour change has a test that fails on dev.
- Full suite: no new failures.
- The report says, for each of the three, fixed / was already fixed / evidence for the lead, with file:line.
