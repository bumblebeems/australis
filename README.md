# Australis .𖥔 ݁ ˖ִ🛸༄˖°.
This is my personal bootable container image built on top of Universal Blue's [Aurora](https://getaurora.dev) (specifically, the Aurora-DX variant).

## Notable Changes
- **Installs additional RPM packages.** See `build_files/packages/add-*.txt` for what exactly is added.
- **Preinstalls Flatpak apps.** This is done using .preinstall files, which can be found under `system_files/usr/share/flatpak/preinstall.d/*`.
- **Removes packages I don't want.** See `build_files/packages/del.txt`.

## Why does this exist?
I used to run Arch on my systems, and whilst I still adore the project I was running into the issue of config drift between my laptop and desktop. I came across two different ways of solving this: NixOS or an immutable OS like Aurora. NixOS was a bit *too* different from a normal Linux distro and I didn't feel like having to learn a bunch of new concepts to use my computer, so it was out. Aurora was close to what I wanted, but I felt it was missing a few packages I like to have. Further research led me to uBlue's guide on how to create your own custom image based off their work, and I realised I could bundle in a few other things I normally set up manually on my systems as well. Hence, Australis was born!

## Why the name "Australis"?
Aurora australis is a name for auroras that occur in the Southern Hemisphere, where I live :3

## I want to make my own!
Have a look at [ublue-os/image-template](https://github.com/ublue-os/image-template) then! That is what I built off to create Australis. There are instructions and resources over there on how to get started too. Have fun!