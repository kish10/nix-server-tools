# Using the `cloud-init.yaml` script

## Create a `cloud-init.yaml` file.

Create a `cloud-init.yaml` file by calling `nix-build cloud_config_creation_utility.nix`, which would output a `cloud-init.yaml` file in a `results` folder.

Note:
- The `cloud_config_creation_utility.nix` file is not perfect, and requires manual intervention for a proper setup.
- For quick use can customize the output file by copying the `cloud_config_creation_utility.nix` & filling in the optional variables such as `users.sshAuthorized` keys.

## Using the `cloud-init.yaml` file to setup a server.

### Provision a server that includes configurations specified in the `cloud-init.yaml` file.

Cloud providers such as `Hetzner` give the option to provide a `cloud-init.yaml` to specify configurations for a server to be created.
(See: [Basic Cloud Config | Hetzner Community](https://community.hetzner.com/tutorials/basic-cloud-config) for details)

### Call `initial_setup` scripts to further configure the server.

Once the server is created:
1. `ssh` into the server.
2. At first login you maybe asked to reset your password, so provide a new password, and ssh again.
3. Call `sudo /initial_setup/install_convenience_programs.sh` to install convenience programs such as `neovim`.
4. Call `sudo /initial_setup/secure_image.sh` to secure the server.
  - Note:
    - Currently, the script is not perfect, so need to make sure the changes are propagated in the `/etc/ssh/ssh_config` file.
      - Ex:
        - In `secure_image.sh` the line `sed -i -e '/^\(#\|\)PermitRootLogin/s/^.*$/PermitRootLogin no/' /etc/ssh/sshd_config`, is supposed to create a line `PermitRootLogin no` in the /etc/ssh/sshd_config -- So make sure the appropriate lines are created.
    - Have to manually run this script instead of through `runcmd`, since for some reason we get locked out of the server when this script is ran by `runcmd`.
4. Call `sudo /initial_setup/install_age.sh` to install `age` (a usefull file encryption tool).
5. Install rootless docker:
  - Copy the file `/initial_setup/install_docker.sh` to the home directory, with `cp /initial_setup/install_docker.sh ~/install_docker.sh`.
  - Change the ownership of the file in the home directory with `chown <username>:<username> ~/install_docker.sh && chmod 700 ~/install_docker.sh`.
    - This is critical since can't install rootless docker under the `root` user, so can't use `sudo install_docker.sh`.
  - Run the file `./install_docker.sh`.
  - Delete the `~/install_docker.sh` file.
5. Call `sudo /initial_setup/install_nix.sh` to install `nix`.

## References

- Documentation: [Cloud-init documentation](https://cloudinit.readthedocs.io/en/latest/index.html)
- Tutorial: [Basic Cloud Config | Hetzner Community](https://community.hetzner.com/tutorials/basic-cloud-config)
