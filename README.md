# DeployFlow

A static website packaged in an Nginx Docker container, deployed to an AWS EC2 instance, and reachable by anyone at `http://YOUR_PUBLIC_IP:8081`.

Built for the Tericsoft DevOps internship task: provision a server, install Docker, containerize an app, open it to the internet on port 8081, and push the code to a public GitHub repository. An optional ECS (Fargate) deployment is covered at the end.

## Contents

1. [Project overview](#1-project-overview)
2. [Technology stack](#2-technology-stack)
3. [Folder structure](#3-folder-structure)
4. [Deployment architecture](#4-deployment-architecture)
5. [The Dockerfile explained](#5-the-dockerfile-explained)
6. [Prerequisites](#6-prerequisites)
7. [Run it locally](#7-run-it-locally)
8. [Push to GitHub](#8-push-to-github)
9. [Deploy to AWS EC2](#9-deploy-to-aws-ec2)
10. [Update and redeploy](#10-update-and-redeploy)
11. [Troubleshooting](#11-troubleshooting)
12. [Cost precautions and cleanup](#12-cost-precautions-and-cleanup)
13. [Deploy on Amazon ECS](#13-optional-bonus-deploy-on-amazon-ecs-fargate)

### Placeholders used in this guide

Replace these with your own values. Everything else can be copied as written.

| Placeholder | What to put there | Example |
| --- | --- | --- |
| `YOUR_GITHUB_USERNAME` | Your GitHub username | `octocat` |
| `YOUR_REPOSITORY_URL` | HTTPS clone URL of your repo | `https://github.com/octocat/tericsoft-devops-task.git` |
| `YOUR_PUBLIC_IP` | Public IPv4 address of your EC2 instance | `13.233.10.20` |
| `YOUR_KEY_FILE.pem` | The key pair file you download when launching EC2 | `deployflow-key.pem` |
| `AWS_REGION` | Region code you deploy in (ECS section only) | `ap-south-1` |
| `AWS_ACCOUNT_ID` | Your 12 digit AWS account ID (ECS section only) | `123456789012` |
| `TASK_PUBLIC_IP` | Public IP of the running ECS task (ECS section only) | `3.110.5.6` |

---

## 1. Project overview

DeployFlow is a single page site about containerized deployment. The page doubles as proof that the deployment works: its first panel reads the address, port, and `Server` header of the very request that loaded it, so on EC2 it shows your public IP, port `8081`, and the Nginx version that answered.

**Features**

* Hero section with a live request panel (real data from the browser and the response, nothing hard coded)
* Animated deployment flow: Source Code, Docker Image, AWS EC2, Browser
* Three feature cards for Docker, AWS EC2, and GitHub
* Technical section explaining the image, the port mapping, and how the container stays up
* Responsive from 320px phones to wide desktops
* Semantic HTML, skip link, visible keyboard focus, and `prefers-reduced-motion` support
* Works with JavaScript disabled (the animation just shows its final state)
* One HTML file. No frameworks, no npm, no build step

## 2. Technology stack

| Layer | Choice | Why |
| --- | --- | --- |
| Website | HTML, CSS, a little vanilla JavaScript | Nothing to compile, nothing to break |
| Web server | Nginx (`nginx:alpine` image) with our own server config | Fast at static files, tiny image, one short config file sets port 8081 |
| Container | Docker | Same image runs on a laptop and on EC2 |
| Cloud server | AWS EC2, Amazon Linux 2023, `t3.micro` | Free Tier eligible, AWS maintained OS, Docker in the default repos |
| Source control | Git and GitHub | Public repo required by the task; the server deploys from it |
| Bonus | Amazon ECR and ECS on Fargate | Managed orchestration, restarts, no server to patch |

Fonts (Archivo and JetBrains Mono) load from Google Fonts. If they can't load, the page falls back to system fonts and still looks fine.

## 3. Folder structure

```text
tericsoft-devops-task/
├── app/
│   └── index.html      The entire website: markup, styles, and a small script
├── nginx/
│   └── default.conf    Nginx server config: listens on 8081, serves app/index.html
├── Dockerfile          Builds the image: Nginx, our config, and app/index.html
├── .dockerignore       Keeps the Docker build context to what the image needs
├── .gitignore          Keeps keys, secrets, archives, and editor files out of Git
└── README.md           This guide
```

## 4. Deployment architecture

```text
 Developer laptop (Windows)            GitHub                     AWS EC2 (Amazon Linux 2023)
 ┌──────────────────────┐   git push   ┌──────────────┐  git clone  ┌──────────────────────────────────┐
 │ app/index.html       │ ───────────▶ │ public repo  │ ──────────▶ │ docker build -t deployflow .     │
 │ Dockerfile           │              └──────────────┘             │ docker run -p 8081:8081 \        │
 └──────────────────────┘                                           │            deployflow            │
                                                                    │  host :8081 ──▶ container :8081  │
                                                                    │                  (Nginx)         │
                                                                    └───────────────▲──────────────────┘
                                                                                    │ allowed by security group:
                                                                                    │ TCP 8081 from 0.0.0.0/0
                                                              Anyone's browser: http://YOUR_PUBLIC_IP:8081
```

How a request reaches the page:

1. A browser asks for `http://YOUR_PUBLIC_IP:8081`.
2. The EC2 security group checks its inbound rules. TCP 8081 is open to everyone, so the packet is let through.
3. Docker on the instance owns host port 8081 and forwards it to port 8081 inside the container (`-p 8081:8081`).
4. Nginx in the container, listening on 8081, answers with `/usr/share/nginx/html/index.html`, which is our `app/index.html`.

### Why Nginx listens on 8081 inside the container

The task says the image must "expose/serve on port 8081". Nginx listens on port 80 by default, so the Dockerfile changes that one setting: the container itself serves on 8081, `EXPOSE 8081` documents it, and the run command publishes the same port on the host with `-p 8081:8081`. The requirement is met by the image itself, not only by how it happens to be run.

The alternative would be leaving Nginx on 80 and running with `-p 8081:80`. That works too and needs no config change, but then the image serves on 80 and only the run command makes it 8081. Keeping one port number end to end (security group, host, container, Nginx) also leaves less to get wrong.

**How the port is set.** The project ships its own `nginx/default.conf` containing `listen 8081;`. The Dockerfile copies it over the image's stock `/etc/nginx/conf.d/default.conf` (which says `listen 80;`), so ours is the only server block Nginx loads and nothing listens on 80. A build step then runs `nginx -t`, so a broken config stops the build instead of producing a container that won't start.

Why a file instead of editing the stock config with `sed` at build time: an earlier version of this project did that, and it worked, but it depended on the exact text of a file we don't control, was hard to read, and its behavior on IPv6 hosts relied on a side effect in the image's startup scripts. A config file you can open and read is explicit, reviewable in Git, and doesn't change when the base image does.

## 5. The Dockerfile explained

```dockerfile
FROM nginx:alpine
```
Starts from the official Nginx image built on Alpine Linux. Alpine keeps the image much smaller than the default Debian based `nginx` tag, which means faster pulls and less software to patch. Run `docker image ls` after building to see the size on your machine. The base image already starts Nginx in the foreground, so we don't need a `CMD`.

```dockerfile
LABEL org.opencontainers.image.title="DeployFlow" ...
```
Metadata only. Shows up in `docker inspect` and doesn't change behavior.

```dockerfile
COPY nginx/default.conf /etc/nginx/conf.d/default.conf
```
Replaces the stock server config with ours. Nginx's main config loads every file in `/etc/nginx/conf.d/`, and the image has exactly one there, `default.conf`. Overwriting that file (instead of adding a second one beside it) is what guarantees the stock port 80 server is gone. Our file:

```nginx
server {
    listen       8081;
    server_name  _;

    root   /usr/share/nginx/html;
    index  index.html;

    location / {
        try_files $uri $uri/ =404;
    }

    error_page   500 502 503 504  /50x.html;
    location = /50x.html {
        root   /usr/share/nginx/html;
    }
}
```

* `listen 8081;` is the whole point: Nginx accepts connections on port 8081.
* `server_name _;` matches any host name, so the site answers whether you visit by IP, `localhost`, or a domain.
* `root` and `index` serve `index.html` from the web root.
* `try_files $uri $uri/ =404;` returns a clean 404 for paths that don't exist.
* The `error_page` block keeps Nginx's stock `50x.html` for server errors.

**Why IPv4 only.** The official image normally adds an IPv6 listener (`listen [::]:80;`) at container start, but only when IPv6 is available. A fixed `listen [::]:8081;` in our file would make Nginx refuse to start on any machine without IPv6 (it fails with `Address family not supported by protocol`). It also isn't needed: Docker's default bridge network gives containers no IPv6 address and forwards published ports to the container over IPv4. The image's IPv6 startup script sees that `default.conf` isn't the stock file and leaves it alone, so our config is used exactly as written.

```dockerfile
COPY app/index.html /usr/share/nginx/html/index.html
```
Copies our page over Nginx's default welcome page in `/usr/share/nginx/html`, the folder our config's `root` points to. The paths on the left of both `COPY` lines are relative to the build context (the folder you run `docker build` in), which is why you must run the build from the project root.

```dockerfile
RUN nginx -t
```
Tests the full Nginx configuration during the build. If anything is invalid, the build fails right here with Nginx's error message, instead of producing an image whose container crashes on start. A successful build prints `syntax is ok` and `test is successful`.

```dockerfile
EXPOSE 8081
```
Documents that the container listens on port 8081. It does **not** open any port by itself. Publishing happens at run time with `-p 8081:8081`.

You'll notice `docker ps` lists `80/tcp` next to `0.0.0.0:8081->8081/tcp`. That's inherited: the `nginx:alpine` base image declares `EXPOSE 80`, and a Dockerfile can't remove an exposed port it inherited. It's only metadata. Nothing listens on 80 inside this container and nothing publishes it, so it's harmless. Be ready to say so if it shows up on camera.

```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD ["wget", "-q", "-O", "/dev/null", "http://127.0.0.1:8081/"]
```
Every 30 seconds Docker fetches the page from inside the container on port 8081. If it fails three times in a row the container is marked `unhealthy`. The JSON (exec) form runs `wget` directly without a shell; `wget` already exits with 1 on failure, which is what Docker expects for unhealthy. `docker ps` shows `(healthy)` once Nginx answers, which is a stronger check than "the process is running". `wget` ships with Alpine's BusyBox, so nothing extra is installed.

**What `.dockerignore` does.** When you run `docker build`, Docker sends the folder to the builder as the "build context". `.dockerignore` keeps `.git`, the README, archives, and any stray `.pem` key out of that context. The image only ever receives `app/index.html` and `nginx/default.conf`.

## 6. Prerequisites

### On your Windows laptop

| Tool | Why | Get it |
| --- | --- | --- |
| Git for Windows | Commit and push code; includes Git Credential Manager for GitHub login | https://git-scm.com/download/win |
| Docker Desktop | Build and test the image locally (uses WSL 2) | https://docs.docker.com/desktop/setup/install/windows-install/ |
| VS Code | Edit files | https://code.visualstudio.com/ |
| OpenSSH client | SSH into EC2. Built into Windows 10 and 11, run `ssh -V` in PowerShell to check | Settings, Optional features, OpenSSH Client |

Docker Desktop on Windows needs WSL 2 and virtualization enabled in BIOS. The installer walks you through it. After installing, start Docker Desktop and wait until it says the engine is running.

### Accounts

* A GitHub account
* An AWS account (a payment method is required at sign up even for Free Tier). Read [section 12](#12-cost-precautions-and-cleanup) before launching anything.

## 7. Run it locally

Open PowerShell (or the VS Code terminal) in the project folder, the one that contains the `Dockerfile`.

**1. Check Docker works**

```powershell
docker version
docker run --rm hello-world
```

**2. Build the image**

```powershell
docker build -t deployflow .
```

The `.` at the end is the build context (the current folder). Don't forget it.

**3. Run the container**

```powershell
docker run -d --name deployflow --restart unless-stopped -p 8081:8081 deployflow
```

| Flag | Meaning |
| --- | --- |
| `-d` | Run in the background (detached) |
| `--name deployflow` | Give it a fixed name so later commands are easy |
| `--restart unless-stopped` | Restart after crashes and after Docker or the machine restarts, unless you stopped it yourself |
| `-p 8081:8081` | Host port 8081 forwards to port 8081 inside the container, where Nginx listens |
| `deployflow` | The image to run |

**4. Test it**

```powershell
docker ps
```

Wait a few seconds until the STATUS column shows `Up ... (healthy)`. Then open **http://localhost:8081** in your browser. The "This request" panel should show `localhost`, port `8081`, and an `nginx/...` version.

From the terminal (PowerShell 7 or Git Bash; in Windows PowerShell 5.1 use `curl.exe` so you don't get the PowerShell alias):

```powershell
curl.exe -I http://localhost:8081
```

You should see `HTTP/1.1 200 OK` and `Server: nginx/...`.

**5. Stop and clean up when done**

```powershell
docker rm -f deployflow
```

## 8. Push to GitHub

**1. Create the repository on GitHub**

Go to https://github.com/new, name it `tericsoft-devops-task`, set it to **Public**, and **don't** tick "Add a README" (you already have one, and an extra commit on GitHub would make your first push fail).

**2. Set your Git identity (first time only)**

```powershell
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

**3. Commit and push**

From the project folder:

```powershell
git init
git add .
git status
git commit -m "Add DeployFlow site, Dockerfile, and deployment guide"
git branch -M main
git remote add origin https://github.com/YOUR_GITHUB_USERNAME/tericsoft-devops-task.git
git push -u origin main
```

Look at the `git status` output before committing. You should see `app/index.html`, `nginx/default.conf`, `Dockerfile`, `.dockerignore`, `.gitignore`, and `README.md`, and nothing else. **Never commit your `.pem` key.** The `.gitignore` already blocks `*.pem`, but keep the key outside the project folder anyway.

GitHub doesn't accept account passwords for `git push`. On Windows, Git Credential Manager opens a browser window to sign in the first time. If you're prompted for a password in the terminal instead, use a personal access token.

Refresh the repo page on GitHub. All six files should be there. Copy the HTTPS clone URL; that's your `YOUR_REPOSITORY_URL`.

## 9. Deploy to AWS EC2

### 9.1 Choose the instance

| Setting | Choice | Reason |
| --- | --- | --- |
| AMI | Amazon Linux 2023 (64-bit x86) | AWS maintained, Free Tier eligible, Docker is in its default package repos |
| Instance type | `t3.micro` | 2 vCPUs, 1 GiB RAM, burstable. Free Tier eligible for both older and newer AWS accounts |
| Storage | 8 GiB gp3 (the default) | The OS plus Docker and this image fit comfortably |
| Region | The one closest to you, e.g. `ap-south-1` (Mumbai) | Lower latency |

**Why this size is enough.** Nginx serving one static file uses only a few megabytes of RAM and almost no CPU. A `t3.micro` has plenty of headroom, and burstable CPU credits cover the short spike during `docker build`. A larger instance would just cost more for no benefit.

Free Tier rules depend on when your AWS account was created (before or after 15 July 2025). Older accounts can use `t2.micro` or `t3.micro`; newer accounts get credits and can use `t3.micro`, `t3.small`, `t4g.micro`, `t4g.small`, and a few others. `t3.micro` works for both, which is why it's the pick here. Check for the **Free tier eligible** label in the console before launching.

### 9.2 Launch the instance

1. Open the EC2 console, check the region in the top right, and choose **Launch instance**.
2. **Name:** `deployflow-server`.
3. **Application and OS Images:** Amazon Linux, then **Amazon Linux 2023 AMI**, architecture **64-bit (x86)**.
4. **Instance type:** `t3.micro`.
5. **Key pair:** choose **Create new key pair**, name it, type **RSA**, format **.pem**. The file downloads once. Keep it safe and outside your project folder.
6. **Network settings:** choose **Edit**.
   * VPC: the default VPC.
   * Auto-assign public IP: **Enable**.
   * Firewall: **Create security group**, name `deployflow-sg`. Set the rules in the next step.
7. **Configure storage:** leave the default 8 GiB gp3.
8. Choose **Launch instance**.

### 9.3 Security group rules

Inbound rules for `deployflow-sg`:

| Type | Protocol | Port | Source | Purpose |
| --- | --- | --- | --- | --- |
| SSH | TCP | 22 | **My IP** | Only your current IP address can SSH in |
| Custom TCP | TCP | 8081 | **Anywhere-IPv4** (`0.0.0.0/0`) | Anyone can open the website |

Leave the outbound rule as the default (all traffic allowed). The instance needs it to download packages, the base image, and your repo.

Why this shape: SSH is the way to control the server, so it's limited to you. Port 8081 is the public face of the app, so it's open to all. Port 80 is **not** opened on the instance because nothing listens on host port 80; Docker only publishes 8081.

If you skipped the rules during launch: EC2 console, **Instances**, select your instance, **Security** tab, click the security group, **Edit inbound rules**.

> Home and mobile internet IPs change often. If SSH suddenly times out, your IP probably changed. Edit the SSH rule and pick **My IP** again.

### 9.4 Connect with SSH from Windows

Find the **Public IPv4 address** on the instance's details page. That's `YOUR_PUBLIC_IP`.

In PowerShell, from the folder that holds your key:

```powershell
ssh -i .\YOUR_KEY_FILE.pem ec2-user@YOUR_PUBLIC_IP
```

Type `yes` when asked to trust the host. The username for Amazon Linux is `ec2-user`.

If SSH refuses the key with **UNPROTECTED PRIVATE KEY FILE**, lock the file down to your user only and try again:

```powershell
icacls .\YOUR_KEY_FILE.pem /inheritance:r
icacls .\YOUR_KEY_FILE.pem /grant:r "$($env:USERNAME):(R)"
```

### 9.5 Show the server specs

Useful for the recording, where you need to show CPU, RAM, and disk. Run on the instance:

```bash
cat /etc/os-release | head -3     # operating system
nproc                             # number of vCPUs
free -h                           # memory
df -h /                           # root disk size and usage
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-type; echo
```

The last two lines ask the instance metadata service (IMDSv2) for the instance type, so you can prove it's a `t3.micro` from inside the server.

### 9.6 Install Docker and Git on Amazon Linux 2023

These steps follow the official AWS guide, [Creating a container image for use on Amazon ECS](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/create-container-image.html), which installs Docker on Amazon Linux 2023. On AL2023, `yum` is an alias for `dnf`, so either works.

```bash
sudo dnf update -y
sudo dnf install -y docker git
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -a -G docker ec2-user
```

What each line does:

* `dnf update -y` installs the latest security updates.
* `dnf install -y docker git` installs the Docker engine and Git from Amazon's repos.
* `systemctl start docker` starts the Docker daemon now.
* `systemctl enable docker` starts it automatically on every boot. The AWS guide only starts it; enabling it matters here because `--restart unless-stopped` can only bring the container back after a reboot if Docker itself starts.
* `usermod -a -G docker ec2-user` lets `ec2-user` run Docker without `sudo`.

**Log out and back in** so the group change applies:

```bash
exit
```

```powershell
ssh -i .\YOUR_KEY_FILE.pem ec2-user@YOUR_PUBLIC_IP
```

**Verify the setup before moving on** (the task asks for this explicitly):

```bash
docker --version
git --version
docker info
docker run --rm hello-world
```

`docker info` should print server details with no permission error, and `hello-world` should print "Hello from Docker!".

### 9.7 Clone, build, and run

```bash
cd ~
git clone YOUR_REPOSITORY_URL
cd tericsoft-devops-task
ls -la
docker build -t deployflow .
docker run -d --name deployflow --restart unless-stopped -p 8081:8081 deployflow
```

`ls -la` should list `app`, `Dockerfile`, `.dockerignore`, `.gitignore`, and `README.md`. If your repo has a different name, `cd` into that folder instead.

### 9.8 Verify the deployment

On the server:

```bash
docker ps
curl -I http://localhost:8081
docker logs deployflow
```

You want `Up ... (healthy)` and `0.0.0.0:8081->8081/tcp` from `docker ps` (an extra `80/tcp` in that column is normal; see section 5), and `HTTP/1.1 200 OK` from `curl`.

Then from your laptop, or your phone on mobile data to prove it's really public, open:

```text
http://YOUR_PUBLIC_IP:8081
```

Type `http://` explicitly. Some browsers try `https://` first, and there's no HTTPS on this server. The "This request" panel should show your public IP and port 8081.

## 10. Update and redeploy

**On your laptop:** edit `app/index.html`, test locally (section 7), then:

```powershell
git add .
git commit -m "Describe your change"
git push
```

**On the server:**

```bash
cd ~/tericsoft-devops-task
git pull
docker build -t deployflow .
docker rm -f deployflow
docker run -d --name deployflow --restart unless-stopped -p 8081:8081 deployflow
docker image prune -f
```

The site is offline for a second or two between `rm` and `run`. That's fine here; zero downtime deploys are one of the things ECS with a load balancer gives you. `docker image prune -f` deletes the old untagged image so the 8 GiB disk doesn't fill up over many deploys.

If the browser still shows the old version, do a hard refresh (Ctrl+F5).

## 11. Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Browser spins and times out on `:8081` | Security group has no rule for 8081, or the rule is on a different security group | Add Custom TCP 8081 from `0.0.0.0/0` to the group attached to this instance |
| `ERR_CONNECTION_REFUSED` on `:8081` | Container isn't running, or it was started without `-p 8081:8081` (for example with `-p 8081:80`, which points at a port Nginx no longer uses) | `docker ps -a`, then `docker logs deployflow`. Remove and rerun with the exact command in 9.7 |
| Browser says the site can't provide a secure connection | Browser upgraded to `https://` | Use `http://YOUR_PUBLIC_IP:8081` |
| Works with `curl` on the server but not from outside | Security group, or you're using the private IP | Use the **Public** IPv4 address; recheck inbound rules |
| `permission denied while trying to connect to the Docker daemon socket` | Group change not applied yet | Log out and back in after `usermod`, or prefix with `sudo` |
| `Cannot connect to the Docker daemon` | Docker service not running | `sudo systemctl start docker`. If it persists, `sudo systemctl status docker` |
| `Bind for 0.0.0.0:8081 failed: port is already allocated` | Another container already uses 8081 | `docker ps -a`, then `docker rm -f <name>` |
| `Conflict. The container name "/deployflow" is already in use` | Old container with the same name | `docker rm -f deployflow`, then run again |
| `docker ps` shows `(unhealthy)` | Nginx isn't answering on 8081 inside the container | `docker logs deployflow`; rebuild with `docker build --no-cache -t deployflow .` |
| Build stops at `RUN nginx -t` | A typo in `nginx/default.conf` (a missing `;` is the usual one); the error line names the file and line number | Fix that line and rebuild |
| `COPY failed: file not found` for `nginx/default.conf` | The `nginx/` folder is missing or misnamed | Check `ls nginx/default.conf` from the project root |
| Nginx's "Welcome to nginx!" page appears | Old image, or build ran from the wrong folder | Run the build from the project root (where `Dockerfile` is) and use `--no-cache` |
| `COPY failed: file not found` during build | Build context is wrong, or `app/` is missing | `cd` into the project root; check `ls app/index.html` |
| SSH: `Connection timed out` | Your IP changed, the instance is stopped, or the public IP changed after a stop and start | Update the SSH rule to **My IP**; check the instance state and its current public IP |
| SSH: `Permission denied (publickey)` | Wrong username or wrong key | User is `ec2-user`; use the `.pem` created with this instance |
| SSH: `UNPROTECTED PRIVATE KEY FILE` (Windows) | Key file permissions too open | Run the two `icacls` commands in 9.4 |
| EC2 Instance Connect in the browser fails | SSH is limited to your IP, and Instance Connect comes from AWS's IP range | Use SSH from your laptop as above |
| Windows: `error during connect ... docker_engine` | Docker Desktop isn't running | Start Docker Desktop and wait for the engine to start |
| `git push` rejected: `fetch first` | Repo on GitHub has a commit you don't have (e.g. a README created there) | `git pull --rebase origin main`, then `git push` |
| `git push` asks for a password and rejects it | GitHub doesn't accept account passwords | Sign in through Git Credential Manager, or use a personal access token |
| Site went down after a reboot | Docker not enabled at boot | `sudo systemctl enable --now docker`; the container comes back on its own thanks to `--restart unless-stopped` |

## 12. Cost precautions and cleanup

Running AWS resources bills your account. Tericsoft isn't responsible for charges, so stay deliberate.

**Before launching**

* Use only instance types marked **Free tier eligible** in the console.
* Create a budget alert: Billing and Cost Management, **Budgets**, **Create budget**, pick the **Zero spend budget** template, and enter your email. You'll be emailed as soon as anything costs money.
* Remember which region you used. Resources in other regions are easy to forget.

**While it runs**

* Public IPv4 addresses are billed hourly by AWS, and Free Tier only covers a limited amount. One instance for a few days is small; forgotten resources for months are not.
* **Stopping** an instance stops compute charges but **not** storage charges for its EBS volume, and the public IP usually changes on the next start.
* Check the EC2 dashboard's **Free Tier** box (older accounts) or the Billing console's credits page (newer accounts).

**Cleanup once your submission is reviewed**

1. **EC2:** Instances, select `deployflow-server`, **Instance state**, **Terminate (delete) instance**. The root volume is deleted with it by default; confirm under **Elastic Block Store, Volumes** that nothing is left.
2. **Security group:** Network and Security, Security Groups, delete `deployflow-sg` (possible only after the instance is gone).
3. **Key pair:** Network and Security, Key Pairs, delete it, and delete the `.pem` from your laptop.
4. **Elastic IP** (only if you allocated one): release it. An unattached Elastic IP still bills.
5. **ECS, if you did the bonus:** see the cleanup steps in 13.6.
6. Use **EC2 Global View** (search for it in the console) to confirm no instances, volumes, or security groups remain in any region.
7. Keep the GitHub repo public until the review is done. It costs nothing.

## 13. Deploy on Amazon ECS (Fargate)

> **Separate from the required EC2 deployment.** Finish and verify sections 9.1 to 9.8 first. Nothing here changes the EC2 setup.

ECS runs containers for you. With the **Fargate** launch type there's no server to manage: you give ECS an image, CPU, and memory, and a **service** keeps the desired number of tasks running, replacing any that stop. That's the scaling, restarts, and orchestration the task PDF mentions.

**Cost note:** Fargate is billed per second for the vCPU and memory a task uses, and ECR billed for image storage. Neither is in the classic always-free tier; newer accounts can spend Free Tier credits on them. A single 0.25 vCPU / 0.5 GB task for an hour or two is cheap, but delete everything as soon as you've recorded it (13.6).

### 13.1 How it differs from EC2

| | EC2 (required) | ECS on Fargate (bonus) |
| --- | --- | --- |
| Where the image comes from | Built on the server from the GitHub repo | Pulled from a registry (Amazon ECR) |
| Who restarts a dead container | Docker's `--restart` policy | The ECS service scheduler |
| Port | Host 8081 mapped to container 8081 | In `awsvpc` mode the host port must equal the container port. Nginx already listens on 8081, so the task is reached on 8081 as well |
| Address | Instance public IP | Task public IP (changes whenever the task is replaced) |

Because the image itself serves on 8081, ECS needs no special handling: set the container port to 8081 and open TCP 8081 on the task's security group.

### 13.2 Give the EC2 instance permission to push to ECR

Pushing from the EC2 instance avoids putting AWS access keys on your laptop. Amazon Linux 2023 comes with the AWS CLI installed.

1. IAM console, **Roles**, **Create role**. Trusted entity: **AWS service**, use case **EC2**.
2. Attach the AWS managed policy **AmazonEC2ContainerRegistryPowerUser**.
3. Name it `deployflow-ec2-ecr` and create it.
4. EC2 console, select the instance, **Actions**, **Security**, **Modify IAM role**, choose `deployflow-ec2-ecr`, **Update IAM role**.

Check it from the instance (wait a minute after attaching):

```bash
aws sts get-caller-identity
```

The `Arn` should mention `deployflow-ec2-ecr`. The `Account` value is your `AWS_ACCOUNT_ID`.

### 13.3 Push the image to Amazon ECR

On the EC2 instance, inside `~/tericsoft-devops-task`, with `deployflow` already built. These follow the same official AWS guide linked in 9.6.

```bash
aws ecr create-repository --repository-name deployflow --region AWS_REGION

aws ecr get-login-password --region AWS_REGION | docker login --username AWS --password-stdin AWS_ACCOUNT_ID.dkr.ecr.AWS_REGION.amazonaws.com

docker tag deployflow:latest AWS_ACCOUNT_ID.dkr.ecr.AWS_REGION.amazonaws.com/deployflow:latest

docker push AWS_ACCOUNT_ID.dkr.ecr.AWS_REGION.amazonaws.com/deployflow:latest
```

The login should print `Login Succeeded`. Your image URI is:

```text
AWS_ACCOUNT_ID.dkr.ecr.AWS_REGION.amazonaws.com/deployflow:latest
```

The image was built on an x86 `t3.micro`, so it's an x86_64 image. That's why the task definition below uses **Linux/X86_64**.

### 13.4 Create the cluster, task definition, and service

All in the ECS console (https://console.aws.amazon.com/ecs/v2), in the same region as the ECR repository.

**Cluster**

1. **Clusters**, **Create cluster**. Name: `deployflow-cluster`. Infrastructure: **AWS Fargate (serverless)** only. **Create**.

**Task definition**

1. **Task definitions**, **Create new task definition**.
2. Family: `deployflow`. Launch type: **AWS Fargate**.
3. Operating system/Architecture: **Linux/X86_64**. CPU: **.25 vCPU**. Memory: **.5 GB**.
4. Task execution role: **Create new role** (ECS creates `ecsTaskExecutionRole`, which lets it pull from ECR and write logs).
5. Container: name `deployflow`, image URI from 13.3, **Essential: Yes**.
6. Port mappings: container port **8081**, protocol **TCP**, app protocol **HTTP**.
7. Leave logging on (CloudWatch). **Create**.

**Security group for the task**

EC2 console, Security Groups, **Create security group**, name `deployflow-ecs-sg`, default VPC, inbound rule **Custom TCP, port 8081, Anywhere-IPv4**.

**Service**

1. Open `deployflow-cluster`, **Services** tab, **Create**.
2. Compute options: **Launch type**, **FARGATE**.
3. Application type: **Service**. Task definition family: `deployflow`, latest revision. Service name: `deployflow-service`. Desired tasks: **1**.
4. Networking: default VPC, keep the public subnets, choose **Use an existing security group** and pick `deployflow-ecs-sg`. Make sure **Public IP** is turned **on**.
5. No load balancer (it would add cost). **Create**.

### 13.5 Verify

1. Wait for the service to show **1/1 tasks running**.
2. Open the **Tasks** tab, click the task, find **Public IP** under Configuration.
3. Open `http://TASK_PUBLIC_IP:8081`. The "This request" panel shows the task's IP and port `8081`.
4. To see orchestration in action: stop the task manually (**Tasks**, select, **Stop**). Within a minute the service starts a replacement with a new IP. That's the self-healing the PDF refers to.

If the task stops right away, open it and read **Stopped reason**:

* `CannotPullContainerError`: image URI typo, missing execution role, or Public IP turned off (the task can't reach ECR).
* `exec format error`: architecture mismatch. Use Linux/X86_64 for an image built on x86.

### 13.6 ECS cleanup

1. Cluster, **Services**, select `deployflow-service`, **Delete service** (choose force delete so it scales to 0 first).
2. **Delete cluster** `deployflow-cluster`.
3. **Task definitions**, `deployflow`, deregister all revisions (then delete them if offered).
4. ECR, **Repositories**, delete `deployflow` (this deletes the stored images).
5. CloudWatch, **Log groups**, delete the `/ecs/deployflow` group.
6. EC2, Security Groups, delete `deployflow-ecs-sg`.
7. IAM: detach `deployflow-ec2-ecr` from the instance (or terminate the instance) and delete the role if you no longer need it.

