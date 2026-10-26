# Security policy

## Supported versions

Zynith has no stable release yet. Security fixes go to the development branch (`main`), and the next build
includes them. Once releases exist, the latest release will be supported.

## Reporting a vulnerability

Please do not report security problems in public issues.

- Use **GitHub's private vulnerability reporting** for this repository (*Security → Report a vulnerability*) where it
  is available.
- Where it is not, open an issue that says only that you have a security report and asks for a private contact.
  Leave out the details; the maintainer will reply with a private channel.

Include what is affected (component, version or commit), how to reproduce it and what an attacker could do with it.
You will get an acknowledgement within a week, and the fix and its disclosure will be coordinated with you.

## Scope

In scope:

- the native shell (`src/`), including the lock screen and its PAM authentication, the clipboard history
  (encrypted at rest), notification handling, IPC and D-Bus interfaces, and plugin capability checks;
- the UI and its plugin (`ui/`), including anything that writes configuration or runs commands;
- the packaging, the session scripts and the ISO (`packaging/`, `iso/`), including what the live image and the
  installed system enable by default.

Out of scope: vulnerabilities in niri, Quickshell, Fedora packages or other upstream projects. Please report those
upstream. A report about how Zynith uses one of them is in scope.

## What the image does by default

The ISO keeps SELinux enforcing and the firewall enabled, and leaves `sshd` disabled. The live user has no password
and is meant only for the live session. The installed system has only the accounts you create in the installer.

## Network services

Zynith sends no telemetry, has no accounts and contacts no service of its own. Nothing is requested at startup. The
features below make requests only when you turn them on or use them:

| Feature | Service | What is sent | When |
|---|---|---|---|
| Weather | Open-Meteo forecast API | the coordinates of your configured location | only once a location is set (none is set by default) |
| Finding a city | Open-Meteo geocoding API | the city name you typed | only when you set a city in Location settings |
| Lyrics in the media panel | LRCLIB | the artist, title, album and length of what is playing | only while lyrics are shown; off by default |
| Album art for YouTube videos | YouTube's image server | the video's id | only when a player reports a YouTube video |
| Calendar | the CalDAV server or ICS address you add | your account's credentials, to that server only | only for accounts you add |
| Plugins | the Git repositories you add as plugin sources | an ordinary Git fetch | only for sources you add; there are none by default |

Options inherited from the native shell's origin that relied on that project's servers are accepted in
configuration files but have no effect: `shell.telemetry_enabled`, `shell.external_ip_enabled`,
`location.auto_locate`, community palette and template catalogues, and Google Calendar sign-in.

The operating system's own services (for example NetworkManager's connectivity check and firmware updates) behave
as they do on Fedora.
