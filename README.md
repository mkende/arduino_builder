# Arduino Builder

This tool is a command line build system for any Arduino compatible
micro-controller or development board. It can uses any core or Arduino library
to build your program either using an Arduino GUI installation or independently.

## Installation

### Install `cpanm`

You need to have Perl installed on your computer as well as the cpanm Perl
package manager. On Windows, the simplest is just to install
[Strawberry Perl](https://strawberryperl.com/) which has both. On linux, the
simplest way is to install them from your package manager. For example on
Debian, Ubuntu, Mint, and other distributions using `apt`, you can do:

```shell
sudo apt-get install perl cpanminus perl-doc
```

Or, on Red Hat, Fedora, CentOS and other distributions using `yum`, you can do:

```shell
sudo yum install perl perl-App-cpanminus perl-doc
```

### Install Arduino Builder

Then, on Linux systems, run the following command:

```shell
sudo cpanm App::ArduinoBuilder -n -L /usr/local --man-pages --install-args 'DESTINSTALLBIN=/usr/local/bin'
```

On Windows system, use:

```shell
cpanm App::ArduinoBuilder -n
```

## Requirements

To use `arduino_builder` you need to have the source files for the Arduino core
and for the libraries that you are using. They can be installed wherever you
want but the simplest is to have them installed with the Arduino GUI program.

If this is the case, `arduino_builder` will try to auto-detect as much of your
environment as possible. Otherwise you might have to point it to the right
places to find these libraries and tools.

## Documentation

The full documentation of the tool is
[available online here](https://metacpan.org/dist/App-ArduinoBuilder/view/script/arduino_builder)
or you can read it locally with `arduino_builder --help`.

The source code contains a minimal example of a project built with Arduino
Builder [here](https://github.com/mkende/arduino_builder/tree/main/example).
