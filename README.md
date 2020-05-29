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

This is at this stage very much a work in progress, but both included backends should work. At the moment usage requires editing the 
key_vault.sh to source the desired backend, and if you wish you may edit the prefix etc, these will be added to some configuration
file later.

For testing you'll need at least `jq` installed and naturally the cli of the desired backend. The easiest way to test is to use supplied
Dockerfile for testing:

```
docker build -t keyvault_test .
```

After build

```
docker run --rm -it keyvault_test
```

Now you should be in shell in which you're able to run ./key_vault.sh
