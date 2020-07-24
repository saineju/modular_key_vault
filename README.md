# Modular key vault
After writing the original [bitwarden key vault](https://github.com/saineju/bitwarden_sshkey_vault), it soon came apparent
that while the script works quite fine, it limits me to one password vault only and I'm one of those crackpots that use
several for different purposes. That's why I decided to try more modular way by separating the vaults to separate modules
that can be added when needed. The key_vault.sh can use any backend as long as the response logic of each backends stay the same.
At this point it might be good to note that while the script is named as key_vault.sh, it itself does not attempt to do any
encryption or decryption, but relies solely on the cli implementations of the vault solutions.

In addition to using different vaults, I wanted to allow different kinds of keys, for example AWS keys, to be stored, so I'm trying
to keep the backend part as generic as possible, but it is highly possible that it will be a work in progress, especially when I start
to add the AWS functionality.

## How to use
When running the key_vault.sh the script will check for existense of ${HOME}/.key_vault/config -file. If the file does not exist, the
script will ask what backend to use and if you wish to modify some default values. These will be written to the config file and the script
will use the config for the future runs. If you later wish to change some of these configurations you may edit the config file or you can
run the script with `configure` switch.

If you have not logged in to your desired backend, the script should first ask for credentials when you run it after configuration. Different
password vaults have different ways for caching their keys, so you should refer to their guides on how to cache the credentials if you wish to
do so.

#### Generate a key

```
key_vault.sh generate --key-name <new_key_name> --key-enc <rsa|ed25519>
e.g.
key_vault.sh generate --key-name my_test --key-enc ed25519
```

The command will create a new key to your chosen backend prefixed with chosen prefix. So if you have opted to keep the default prefix, you should have
key key_vault/my_test in your password store. The script will output public key for the created key.

If you omit --key-name and/or --key-enc switches, they will be asked.

#### Fetch a key

```
key_vault.sh get_key --key-name <searched_key_name>
e.g.
key_vault.sh get_key --key-name my_test
```

This will fetch key named my_test from the chosen backend. Note that you do not have to add the prefix for the key, that will be done automatically. However
you can add the prefix if you wish, it does not affect the search. If the key name will match to several keys, a list of keys will be shown from which you can
select the preferred key.

The fetched key will be added to ssh-agent for the duration of the default ttl that is defined in the configuration file. You may change this with --ttl -switch

If you wish to get the public key instead of private key, you need to use get_public_key -switch. This will just print out the public key.

#### Full help

```
Usage: ./key_vault.sh <list|generate|get_key|get_public_key> [-k key_name] [-t ttl] [-e encryption_type]
	list		List keys in vault
	search		Search for key name, useful if there are more than one matches
	generate	Generate new key to vault
	get_key		Get private key to ssh-agent
	get_public_key	get public key for the specified key
	configure	edit the configuration file
	-k|--key-name	Name for key, required for generating key or getting the key
	-i|--id		Use key ID to fetch the key
	-n|--no-prefix	Do not add key prefix
	-t|--ttl	How long private key should exist in agent, uses ssh-agent ttl syntax
	-e|--key-enc	Key type, accepts rsa or ed25519
	All required parameters will be asked unless specified with switch
```

## vssh -script
The repository contains also a wrapper script for ssh called `vssh`. You may use this script similarly you would use `ssh`, but this script will
intercept -i switch and tries to find the key from the key vault instead. If `-i` is not specified the script attempts to find key that is named
similarly to the server you're connecting to. You can also specify -ttl -switch to alter the default ttl for the key that will be added to ssh-agent.

## Docker for testing
For testing you'll need at least `jq` installed and naturally the cli of the desired backend. The easiest way to test is to use supplied
Dockerfile for testing:

```
docker build -t keyvault_test .
```

After build

```
docker run --rm -it keyvault_test
```

Now you should be in shell in which you're able to run ./key_vault.sh. This container is mostly intended for testing the script easily, so the changes made
to the container will not be persistent. However if you wish, you may mount a local file path for example for /root -directory to make things persistent.

