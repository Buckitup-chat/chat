#!/bin/bash

if [ `hostname` = 'eco' ]; then
  export SECRET_KEY_BASE=IGuZPUcM7Vuq1iPemg6pc7EMwLLmMiVA4stbfDstZPshJ8QDqxBBcVqNnQI6clxi
  export MIX_ENV=prod
  export PORT=80
  export PHX_SERVER=true
  export DOMAIN=eco-taxi.one

  . $HOME/.asdf/asdf.sh
  cd chat 
  git pull
	npm install --prefix ./assets
	mix deps.get --only prod
	mix do compile, assets.deploy
  mix phx.gen.release
  MIX_ENV=prod mix release --overwrite
  sudo systemctl restart eco.service

  sudo systemctl status eco.service
  sleep 3
  sudo systemctl status eco.service




else
  scp host_eco.sh b_eco_server:
  ssh b_eco_server "bash -l host_eco.sh"
fi


