# Claude Specifics for Sec Gcp Logalerting Manage

## Context & Tuning
- Follow `SKILL.md`'s SAD KITTI branches and validate filters against representative logs before proposing a policy.
- Keep notification credentials outside policy files and use only configured incident channels.
- Test alert delivery in an approved sandbox and record the owner and response action.

## Instructions Overrides
- Require approval before changing production notification or paging behavior.

## Performance Notes
- Load only the detection examples relevant to the event being monitored.
