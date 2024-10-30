# 🧊 Alloy DevBox
Automated script magic for configuring machines, vms, or containers
for [alloy](https://github.com/StullerInc/alloy) development.

![DevBox Demo](../assets/devbox-demo.gif?raw=true)

## 🧊 Basic Instructions

Note: *Scroll down for instructions for specific environments*

There are no install dependencies other than your target environment must be running **Ubuntu 22.04 LTS**
or higher. Setup is performed by simply running one of the following cURL or Wget commands on the target machine, VM, or container.

```sh
bash <(curl -so- https://raw.githubusercontent.com/heathprovost/alloy-devbox/main/devbox.sh)
```

```sh
bash <(wget -qO- https://raw.githubusercontent.com/heathprovost/alloy-devbox/main/devbox.sh)
```

Running either of the above commands downloads the script and runs it. By default you will be promted to
provide a few options, but you can create a file called `~/.devboxrc` to provide default responses for 
unattended installs if you prefer. The first time you run the script this file will be created automatically
to store your configuration settings for future use.

#### 🔹Example ~/.devboxrc

```env
name = Jay Doe
email = jay_doe@domain.com
token = ghp_YourGithubTokenForNpmPackageInstalls
```

## 🧊 Windows Using [WSL2](https://learn.microsoft.com/en-us/windows/wsl/install)

Begin by opening a powershell or cmd session in your terminal application.

#### 🔹*Optional: Unregister Ubuntu Distribution*

If you want to start from scratch with a brand new installation you can run the following command before
proceeding, but please be aware that ${{\color{red}\textsf{existing files in your current ubuntu installation will be deleted!}}}\$

```powershell
wsl --unregister Ubuntu
```

#### 🔹Install Ubuntu

Now run the following commands to install using the current Ubuntu LTS distribution:

```powershell
wsl --update
wsl --install -d Ubuntu
```

After this part is done you will be in a bash shell. Type `exit` to return to your original powershell 
or cmd session. Now run this to ensure your new install is set as the default:

```powershell
wsl --setdefault Ubuntu
```

#### 🔹Run DevBox

Close your terminal and open a **new** bash terminal before running the devbox script.

```sh
bash <(curl -so- https://raw.githubusercontent.com/heathprovost/alloy-devbox/main/devbox.sh)
```
or

```sh
bash <(wget -qO- https://raw.githubusercontent.com/heathprovost/alloy-devbox/main/devbox.sh)
```

## 🧊 MacOS Using [OrbStack](https://orbstack.dev)

#### 🔹Install Ubuntu

This will create an Ubuntu machine called "alloy" and then open an ssh session to it:

```sh
orb create ubuntu alloy && ssh alloy@orb
```

#### 🔹Run DevBox

Now just run the devbox script:

```sh
bash <(curl -so- https://raw.githubusercontent.com/heathprovost/alloy-devbox/main/devbox.sh)
```
or

```sh
bash <(wget -qO- https://raw.githubusercontent.com/heathprovost/alloy-devbox/main/devbox.sh)
```