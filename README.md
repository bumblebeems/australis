# ༄˖°.🪐.ೃ࿔*:･ Australis .𖥔 ݁ ˖ִ🛸༄˖°.
This is my personal bootable container image built on top of Universal Blue's [Aurora](https://getaurora.dev) (specifically, the Aurora-DX variant).

## Notable (and very opinionated) changes
- **Extra packages.** A bunch of RPMs and Flatpaks I would spend an hour or so installing + setting up anyway, including:
    - **RPM:** K3b, Resources, Starship, Steam, Zoxide... (see `build_files/rpm/add-*.txt`).
    - **Flatpak:** Chromium, Nicotine+, Prism Launcher, SysD Manager, Zen... (see `build_files/flatpak/add.txt`).
- **Fewer packages too.** I removed packages I never saw myself using from the base image, like Kate (nano, KWrite and VSCode have me covered there). See `build_files/rpm/del.txt` for the full list.
- **Troublesome ujust recipes disabled.** Some of Aurora's (`install-system-flatpaks`, `rebase-helper` and `toggle-devmode`) *really* don't expect to be outside of their native habitat!
- **IBM Plex fonts included.** It's my favourite font and I would have installed it anyway! It also includes Nerd Font-patched IBM Plex Mono.
- **A nicer nano.** My personal config (line wrapping, 4-space tabs, auto-indenting etc.) as well as [Galen Guyer's improved syntax highlighting definition files](https://github.com/galenguyer/nano-syntax-highlighting).
- **furyctl.py.** A script I use to disable the RGB on my Kingston FURY DDR5 RAM (although it can also be used to set static colours). A systemd service to turn the RGB off at boot is included (off by default); it's hardcoded to slots 2 and 4 though!

## Why does this exist?
I used to run Arch on my systems, and whilst I still adore the project I was running into the issue of config drift between my laptop and desktop. I came across two different ways of solving this: NixOS or an immutable OS like Aurora. NixOS was a bit *too* different from a normal Linux distro and I didn't feel like having to learn a bunch of new concepts to use my computer, so it was out. Aurora was close to what I wanted, but I felt it was missing a few packages I like to have. Further research led me to uBlue's guide on how to create your own custom image based off their work, and I realised I could bundle in a few other things I normally set up manually on my systems as well. Hence, Australis was born!

## Why the name "Australis"?
Aurora australis is the name for aurorae seen in the Southern Hemisphere, where I live. It also cleverly conveys what this image is: *aurora* is a broader term whilst *aurora australis* (what the image identifies itself as) is more specific, just like how this image is more specific to me :D

## I want to make my own!
Have a look at [ublue-os/image-template](https://github.com/ublue-os/image-template) then! That is what I built off to create Australis. There are instructions and resources over there on how to get started too. Have fun!