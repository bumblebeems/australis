# Disable and hide dangerous ujust recipes bundled in Aurora by overriding them

[private]
devmode: toggle-devmode

[private]
install-system-flatpaks:
    @echo "install-system-flatpaks is disabled: Australis uses .preinstall files to install system flatpaks." >&2
    @exit 1

[private]
toggle-devmode:
    @echo "toggle-devmode is disabled: Australis does not have a separate developer image." >&2
    @exit 1

[private]
rebase-helper:
    @echo "rebase-helper is disabled: use bootc to rebase to a different image." >&2
    @exit 1