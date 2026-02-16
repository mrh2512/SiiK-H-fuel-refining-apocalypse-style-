fx_version 'cerulean'
game 'gta5'

author 'SiiK'
description 'Oil pumping, refining, SQL persistent pumpjacks/refineries/drums + charged jerrycans + vehicle fuel'
version '4.3.1'

ui_page 'html/index.html'

shared_scripts { 'config.lua' }

client_scripts { 'client/main.lua' }

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'server/main.lua',
}

files {
  'html/index.html',
  'html/style.css',
  'html/app.js',
}

dependencies {
  'qb-core',
  'oxmysql'
}

lua54 'yes'
