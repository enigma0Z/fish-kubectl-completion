# Kubectl completion for Fish

Autocomplete script for [fish](https://fishshell.com/)

## Installation

* Copy the file `kubectl.fish` to `~/.config/fish/completions/`
* Restart your fish session or open a new one

## Usage

When the autocomplete runs for the first time, it parses the kubernetes help
output and generates a large number (over 500, so far) of Fish completions.
This file is then cached at `~/.kube/complete.fish` and subsequent loads come
from here if the file is present.

If you need to regenerate the cached completions, run the following command, and
on the next shell start up, they'll be regenerated:

```fish
set -U __kubectl_regenerate_autocomplete 0
```

## Features

* Suggest all command line switches from kubectl and first-level subcommands
  (ex: `kubectl get`)
* Suggest resources (current context only) from `kubectl get`,
  `kubectl describe`, and `kubectl logs`)
* Suggest files for any `-f` option that is a `--filename`

## TODO

* Auto complete of second-level sub commands (ex: `kubectl rollout history`)
* Auto complete suggestions for options where it makes sense (ex: `-o yaml`)
  * Done: `--output`, still searching for other opportunites here
