# magctrl

`magctrl` controls the light on a MagSafe 3 charging connector.

Use one of these modes:

| Command | Result |
|---|---|
| `magctrl auto` | macOS controls the light. |
| `magctrl amber` | The light stays amber. |
| `magctrl green` | The light stays green. |
| `magctrl off` | The light stays off. |

Use `magctrl status` to show the selected mode.

## Requirements

- An Apple silicon MacBook with MagSafe 3
- macOS 14 or later
- Xcode Command Line Tools

Use this command to install the build tools:

```console
$ xcode-select --install
```

## Build

Clone the repository:

```console
$ git clone https://github.com/fiskebolle99/magctrl.git
$ cd magctrl
```

Build `magctrl`:

```console
$ ./scripts/build-release.sh
```

The build command creates `dist/magctrl`.

## Install

Install `magctrl`:

```console
$ sudo ./dist/magctrl install
```

Enter your administrator password when macOS asks for it.

The install command starts the `magctrl` daemon. The daemon starts again when
the Mac starts.

The selected mode stays active after a restart.

## Use

Select a mode:

```console
$ magctrl amber
$ magctrl green
$ magctrl off
$ magctrl auto
```

Show the selected mode:

```console
$ magctrl status
```

## Remove

Remove `magctrl`:

```console
$ sudo magctrl uninstall
```

The remove command returns the light to `auto` mode.

## Credits and license

`magctrl` adapts AppleSMC code from
[MagHue](https://github.com/kamenlevi/MagHue) by Kamen Levi.

The source revision is
[`b102ed78c61b337ab43c89382a4fad7007a6f084`](https://github.com/kamenlevi/MagHue/commit/b102ed78c61b337ab43c89382a4fad7007a6f084).

See [NOTICE](NOTICE) for more credit information.

This project uses the GNU General Public License, version 3 or later. See
[LICENSE](LICENSE).
