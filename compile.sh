#! /bin/sh

set -e

mix deps.unlock hpax mint
mix deps.clean hpax mint
mix deps.unlock --unused
mix deps.clean --unused
mix deps.get
mix compile
