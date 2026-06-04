# Setup Guide: GitHub Actions CI/CD with AWS ECR

This guide outlines the steps required to configure your GitHub repository and trigger the automated build, push, and remote SSH deployment pipeline.

---

## 🔐 1. Configure GitHub Secrets

Go to your repository on GitHub and navigate to **Settings > Secrets and variables > Actions**. Under the **Secrets** tab, click **New repository secret** to add the following:

| Secret Name | Description / Value |
| :--- | :--- |
| **`AWS_ACCESS_KEY_ID`** | The AWS IAM Access Key ID used by GitHub Actions to push images to ECR. |
| **`AWS_SECRET_ACCESS_KEY`** | The corresponding AWS IAM Secret Access Key. |
| **`SSH_PRIVATE_KEY`** | The exact content of your private key PEM file (e.g., `freeswitch-key.pem` or `asterisk-key.pem`) used to authenticate SSH sessions. |

---

## ⚙️ 2. Configure GitHub Variables

Switch to the **Variables** tab (next to Secrets) and click **New repository variable** to configure the following non-sensitive inputs:

| Variable Name | Example / Target Value |
| :--- | :--- |
| **`AWS_REGION`** | `ap-northeast-1` (or your target AWS region) |
| **`BASTION_IP`** | `52.69.97.143` (the public IP of your Bastion host) |
| **`PRIVATE_SERVER_IP`** | `10.0.1.143` (the private IP of your backend server) |
| **`ECR_REPOSITORY_LEAD_SERVICE`** | `freeswitch-lead-service` (for FreeSWITCH) or `asterisk-lead-service` (for Asterisk) |

---

## 🚀 3. How to Trigger a Deployment

The deployment pipeline is **tag-based** and will not run on normal branch pushes. To trigger a deployment:

1. Commit all your changes and push them to GitHub.
2. Create and push a git version tag with a prefix matching `v*`:

### For FreeSWITCH Stack:
```bash
# Tag the commit (use a tag containing 'freeswitch')
git tag v1.0.0-freeswitch

# Push the tag to GitHub to trigger the pipeline
git push origin v1.0.0-freeswitch
```

### For Asterisk Stack:
```bash
# Tag the commit (use a tag containing 'asterisk')
git tag v1.0.0-asterisk

# Push the tag to GitHub to trigger the pipeline
git push origin v1.0.0-asterisk
```

---

## 📊 4. Monitoring the Run

Once the tag is pushed:
1. Navigate to the **Actions** tab of your repository on GitHub.
2. You will see a workflow run titled **"Deploy Telephony Services to AWS"** in progress.
3. You can click on the running job to watch real-time console logs of the Maven build, Docker compile, ECR push, and remote docker-compose refresh.
