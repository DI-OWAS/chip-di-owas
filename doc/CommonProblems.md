# Common Problems for OWAS Developers

## Container build and execution

### Disabled user namespaces
Building and running the OWAS container requires your system to support user namespaces.
In case of permission errors, make sure they are enabled by checking that `kernel.unprivileged_userns_clone=1`:

```shell
sudo sysctl kernel.unprivileged_userns_clone
```

If the issue persists, AppArmor might be in your way.
You can (temporarily) disable it with

```shell
sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0
```
