#!/bin/bash

if [ `hostname` = 'eco' ]; then
  export SECRET_KEY_BASE=IGuZPUcM7Vuq2iPemg6pc7EMwLLmMiVA4stbfDstZPshJ8QDqxBBcVqNnQI6clxi
  export MIX_ENV=prod
  export PORT=4402
  export PHX_SERVER=true
  export DOMAIN=buckitup.xyz
  export RELEASE_NAME=staging_chat

  # . $HOME/.asdf/asdf.sh
  cd chat 
  git pull
	mix deps.get --only prod
	mix do compile, assets.setup, assets.deploy
  mix phx.gen.release
  MIX_ENV=prod mix release --overwrite
  sudo systemctl restart staging.service

  sudo systemctl status staging.service
  sleep 3
  sudo systemctl status staging.service




else
  scp host_staging.sh b_eco_staging:
  ssh b_eco_staging "bash -l host_staging.sh"
fi


