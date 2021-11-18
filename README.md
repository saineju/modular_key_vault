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
Usage: /data/key_vault.sh <list|generate|get_key|get_public_key> [-k key_name] [-t ttl] [-e encryption_type]
	list		List keys in vault
	search		Search for key name, useful if there are more than one matches
	generate	Generate new key to vault
	get_key		Get private key to ssh-agent
	get_public_key	get public key for the specified key
	get_vault_token	Outputs vault token, can be used for getting the token to env
	configure	edit the configuration file
	import		import existing data from either file or by being asked
	unseal		Unseal hashicorp vault
	-k|--key-name	Name for key, required for generating key or getting the key
	-i|--id		Use key ID to fetch the key
	-n|--no-prefix	Do not add key prefix
	-t|--ttl	How long private key should exist in agent, uses ssh-agent ttl syntax
	-e|--key-enc	Key type, accepts rsa or ed25519
	-b|--backend	Backend to use instead of the default one
	-m|--mode	what key mode should be used, selections: ssh-key,aws,password
	-f|--file	File to import
	-u|--url	Use different url for key vault if applicable (default: https://localhost:8200)
	-kv|--key-vault	Hashicorp key vault path (default: default_kv)
	All required parameters will be asked unless specified with switch
```

## vssh -script
The repository contains also a wrapper script for ssh called `vssh`. You may use this script similarly you would use `ssh`, but this script will
intercept -i switch and tries to find the key from the key vault instead. If `-i` is not specified the script attempts to find key that is named
similarly to the server you're connecting to. You can also specify -ttl -switch to alter the default ttl for the key that will be added to ssh-agent.

## Docker for testing
There is a complete docker for testing purposes available, the docker will contain all required scripts as well as a local hashicorp vault installation to do testing with.

Creating a testing environment you will need naturally Docker and docker-compose, start the environment with
```
docker-compose -f docker-compose-example.yml up -d
```

This should download a fresh version of hashicorp vault docker, do an initial setup for the vault and prints out required passwords. Before proceeding take note of the
unseal password and administrator user password:

```
docker-compose -f docker-compose-example.yml logs|grep -E "(password for admin:|unseal key:)"
```

To get to testing part, easiest way is to just start a shell in the docker, unseal the vault and proceed with that:

```
docker-compose -f docker-compose-example.yml exec key-vault bash
key_vault.sh unseal
export VAULT_TOKEN=$(key_vault.sh get_vault_token)
key_vault.sh -h
```

## Examples

SSH Key

```
## Generate
key_vault.sh generate -m ssh-key -k test-ssh -e rsa
Generated secret key_vault/test-ssh
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCrMzQhwhkTqyGrfaIJcyjKdNxjRWz4EHFijxibeaYq6YL8v3UuTr/XcY2QYaI8dec9hLN6eJ9nbEzHNnVe6ybzn44YgHOFtzzuSrvczNUo9RM1dTp6Amwszf2CKqfRrQAMWq/buCwIUysDjRzbX/O+jjUxRegN/KXhbZUjjRu/xUHXFjtfBht7gFTstvqM2ncLr22SHNhf0FBu7mLzJ9RSsOtKiOcY4k5xA35orGYV8HEGhJx2LlG7Zly0EROhfonpMUsRpVFvwICcBXB0eiPY/YHiIXeOqX7Op5S/3g9bkdT1PuedBazon7SyWSsl+tf1j99EJTqoUFX/gDRqUkmC4TVp1EwTPjQQoVbxWmlWN3cOnVY4zDUlZ7z+C4mostrC0TLpibnqvg813c84lGvuhQp3lnYeFWK8NvFmmxFl503Srj7LWFnHyI1mEFHXAt7f6jo5vSEs+Psmk2HmGrbdkLTd+YrnLN36ZIwYBZjqW0rSh8OWrloL2wqkDbKAJddVrAOsiMNHOBRKjtHHG2abebjvI/SFPmXZRXd3l4DJr/IK/A8057ZGNwe5Z9XE/Na2Z84K4axeSwXPlTZlSyDD5NhI54ptk+Il2+8noUlmG012QnB3bYaKdOyBQnx1sRd8YV6TldBH84ldyIzDZoekJQrW4bwQ47RBnDxWFlcLtw== root@74df81562c6a

## Import
key_vault.sh import -m ssh-key -k imported-ssh -f testi
Enter passphrase:
Generated secret key_vault/imported-ssh
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCoc1949kEsDS9csVD8UFuYr5aJpJqw02DFRWxMIzwri0KBmuAEt4hV5aQHilgIepYmwIZGZ2IsRF4AbaDf5tCgJUhzTl3B9BwSo+f4PqUCENHQj3rnwmmXq4Dg4Pma+aW/ShvChFZBEJrkSAXaCA6rU19HBoKNrfAh8eA/xzr45FrBCgsn4/rV2cqZjnQVUzTdeT+btd676fkbFBUkEqXHYjnwbj/5pwJZWxhWI9rB7IjIYmuGAh0P2Q5xMZ+KPH2acAVazwUisyj8YeRV8anyJib/dCgtXtmTpjTNfGB9xiUs8KzAmd352h2UJ8AviwUvG4r0FthTNz+qnNpeWiGVM7QN6H3basiwMfSD4s3qd9eoMwpKBTwnmWWTa/fQWR4dIi8Q+0UDJIo8byC88fAeuYbBg8HKQAnXAepv8A12LDzNkc8IO8FTSRNVG8Pe+qlAe7Pg6422FcaAv2y10rgW666pUOQ17RwBGLAkDsmqMG0pieej+DARV8OHHb+/ZD5SYhvOexfgELFT+iQXeTVFWFaI3t89BqoVJ2Gh0Dkrz4Xg18UFPsBWfnttI80YcFnguLoa51G+fDsq1Ln/eCziNnz52EgKyg29RVpDEIMmCaGoJA+RAG0Np0kzCs8luKeMYLW1tEG7mVSxIfUvF+pIRakfQucd8Td0TAdcBc4fbw== root@74df81562c6a

## Get to SSH agent
key_vault.sh get -m ssh-key -k test-ssh
Identity added: (stdin) (root@74df81562c6a)
Lifetime set to 3600 seconds
```

AWS Tokens

```
## Importing aws credentials (The CSV needs to be in AWS provided format)
key_vault.sh import -m aws -f /tmp/awskeys.csv -k test-aws
Generated secret key_vault/test-aws

## Providing the aws tokens manually
key_vault.sh import -m aws -k manual-aws
Please enter aws key id:
Please enter aws secret access key: Generated secret key_vault/manual-aws

## Get AWS tokens (Gets session token with the provided key, output is in credential_process format)
key_vault.sh get -m aws -k manual-aws
{
  "AccessKeyId": "<redacted>",
  "SecretAccessKey": "<redacted>",
  "SessionToken": "<redacted>",
  "Expiration": "2021-11-16T14:43:40Z",
  "Version": 1
}

## Using with AWS credentials file
[test-profile]
credential_process = /path/to/key_vault.sh get -m aws -k manual-aws
```

Password / general secrets

```
## Generate
key_vault.sh generate -m password -k test-pass
Generated secret key_vault/test-pass

## Import password from file
key_vault.sh import -m password -f testfile -k imported-pass
Generated secret key_vault/imported-pass


## Manually provide password
key_vault.sh import -m password -k second-imported-pass
Please enter password to be stored: Generated secret key_vault/second-imported-pass

## Get password
key_vault.sh get -m password -k test-pass
aFVB+wTg5+FUq61pkLB8K9DQt/31k4caN/fc3BPg5HEU

## Get password
key_vault.sh get -m password -k test-pass
aFVB+wTg5+FUq61pkLB8K9DQt/31k4caN/fc3BPg5HEU
```
