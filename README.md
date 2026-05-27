================================================================================

# FreeMP Addon — Using Your Own account_id and access_key

================================================================================

#### NOTE: NOT PROVIDED BY ANDROODEV. See: [https://freemp.sleepless.com](https://freemp.sleepless.com)

## What is FreeMP?

FreeMP is a free multiplayer game server hosting service for Godot. The
FreeMP addon connects your Godot game to these servers using an
account_id and access_key pair, so you can add multiplayer without
hosting your own infrastructure.

## Who is FreeMP for?

FreeMP is for Godot developers who want to add multiplayer to their
games without running their own game servers. If you want to try
networked play quickly or prototype a multiplayer concept, FreeMP
handles the server side.

## Demo Godot Project

The demo project (res://demo/) shows a working example of how to use FreeMP.
Note: The demo project uses FreeMP as an autoload (Project > Project Settings > Autoload)

## Get An Account ID

You must get an account ID for your game before using FreeMP.
Go to https://freemp.sleepless.com and follow the simple instructions.

## Using FreeMP in Your Own Game

Copy the FreeMP addon from the demo project into your own project.

The FreeMP addon exposes these properties (all set before calling the connect_to_server function):

- host : Server hostname (default: "example.com")
- port : Server port (default: 443)
- use_ssl : Use wss:// vs ws:// (default: true)
- account_id : Your claimed Account ID
- access_key : Your Access Key from the email

If using FreeMP as an autoload (Project > Project Settings > Autoload):

FreeMP.account_id = "YourAccountId"
FreeMP.access_key = "your_access_key_from_email"
FreeMP.host = "freemp.sleepless.com"
FreeMP.port = 443
FreeMP.use_ssl = true
FreeMP.connect_to_server()

If you add a FreeMP node to your scene tree, you can set account_id and
access_key in the Inspector. The node type is registered when the addon
is enabled (Project > Project Settings > Plugins > FreeMP).
