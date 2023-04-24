# Arduino Builder

This tool is a command line build system for any Arduino compatible
micro-controller or development board. It can uses any core or Arduino library
to build your program either using an Arduino GUI installation or independently.

## Installation

You need to have Perl installed on your computer as well as the cpanm Perl
package manager. On Windows, the simplest is just to install
[Stawberry Perly](https://strawberryperl.com/) which has both. On linux, the
simplest way is to install them from your package manager. For example on
Debian, Ubuntu, Mint, and other distributions using `apt`, you can do:

```shell
sudo apt-get install perl cpanminus
```

On Red Hat, Fedora, CentOS and other distributions using `yum`, you can do:

```shell
sudo yum install perl perl-App-cpanminus
```

Then, on all systems, open a command window or a shell and type:

```shell
cpanm App::ArduinoBuilder
```

## Requirements

To use `arduino_builder` you need to have the source files for the Arduino core
and for the libraries that you are using. They can be installed wherever you
want but the simplest is to have them installed with the Arduino GUI program.

If this is the case, `arduino_builder` will try to auto-detect as much of your
environment as possible. Otherwise you might have to point it to the right place
to find these libraries and tools.

## Command line documentation

For the full documentation of the command line of the tool as well as the
documentation of its configuration files. You can either call
`arduino_builder --help` or read
[this help online](https://metacpan.org/dist/App-ArduinoBuilder/view/script/arduino_builder).
