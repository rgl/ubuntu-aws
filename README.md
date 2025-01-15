# About

This builds an Amazon AWS EC2 Ubuntu Image.

This is based on [Ubuntu 22.04 (Jammy Jellyfish)](https://wiki.ubuntu.com/JammyJellyfish/ReleaseNotes).

# Usage

Install the dependencies:

* [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html).
* [Packer](https://www.packer.io/downloads.html).
* [Terraform](https://www.terraform.io/downloads.html).

Set the AWS Account credentials using SSO, e.g.:

```bash
# set the account credentials.
# NB the aws cli stores these at ~/.aws/config.
# NB this is equivalent to manually configuring SSO using aws configure sso.
# see https://docs.aws.amazon.com/cli/latest/userguide/sso-configure-profile-token.html#sso-configure-profile-token-manual
# see https://docs.aws.amazon.com/cli/latest/userguide/sso-configure-profile-token.html#sso-configure-profile-token-auto-sso
cat >secrets.sh <<'EOF'
# set the environment variables to use a specific profile.
# NB use aws configure sso to configure these manually.
# e.g. use the pattern <aws-sso-session>-<aws-account-id>-<aws-role-name>
export aws_sso_session='example'
export aws_sso_start_url='https://example.awsapps.com/start'
export aws_sso_region='eu-west-1'
export aws_sso_account_id='123456'
export aws_sso_role_name='AdministratorAccess'
export AWS_PROFILE="$aws_sso_session-$aws_sso_account_id-$aws_sso_role_name"
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_DEFAULT_REGION
# configure the ~/.aws/config file.
# NB unfortunately, I did not find a way to create the [sso-session] section
#    inside the ~/.aws/config file using the aws cli. so, instead, manage that
#    file using python.
python3 <<'PY_EOF'
import configparser
import os
aws_sso_session = os.getenv('aws_sso_session')
aws_sso_start_url = os.getenv('aws_sso_start_url')
aws_sso_region = os.getenv('aws_sso_region')
aws_sso_account_id = os.getenv('aws_sso_account_id')
aws_sso_role_name = os.getenv('aws_sso_role_name')
aws_profile = os.getenv('AWS_PROFILE')
config = configparser.ConfigParser()
aws_config_directory_path = os.path.expanduser('~/.aws')
aws_config_path = os.path.join(aws_config_directory_path, 'config')
if os.path.exists(aws_config_path):
  config.read(aws_config_path)
config[f'sso-session {aws_sso_session}'] = {
  'sso_start_url': aws_sso_start_url,
  'sso_region': aws_sso_region,
  'sso_registration_scopes': 'sso:account:access',
}
config[f'profile {aws_profile}'] = {
  'sso_session': aws_sso_session,
  'sso_account_id': aws_sso_account_id,
  'sso_role_name': aws_sso_role_name,
  'region': aws_sso_region,
}
os.makedirs(aws_config_directory_path, mode=0o700, exist_ok=True)
with open(aws_config_path, 'w') as f:
  config.write(f)
PY_EOF
unset aws_sso_start_url
unset aws_sso_region
unset aws_sso_session
unset aws_sso_account_id
unset aws_sso_role_name
# show the user, user amazon resource name (arn), and the account id, of the
# profile set in the AWS_PROFILE environment variable.
if ! aws sts get-caller-identity >/dev/null 2>&1; then
  aws sso login
fi
aws sts get-caller-identity
EOF
```

Or, set the AWS Account credentials using an Access Key, e.g.:

```bash
# set the account credentials.
# NB get these from your aws account iam console.
#    see Managing access keys (console) at
#        https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_access-keys.html#Using_CreateAccessKey
cat >secrets.sh <<'EOF'
export AWS_ACCESS_KEY_ID='TODO'
export AWS_SECRET_ACCESS_KEY='TODO'
unset AWS_PROFILE
# set the default region.
export AWS_DEFAULT_REGION='eu-west-1'
# show the user, user amazon resource name (arn), and the account id.
aws sts get-caller-identity
EOF
```

Append more secrets:

```bash
cat >>secrets.sh <<EOF

export CHECKPOINT_DISABLE='1'
export PKR_VAR_region='eu-west-1'
export PKR_VAR_image_name='rgl-ubuntu'
export TF_VAR_region="\$PKR_VAR_region"
export TF_VAR_vpc_name="\$PKR_VAR_image_name"
export TF_VAR_image_name="\$PKR_VAR_image_name"
export TF_VAR_admin_ssh_key_data="\$(cat ~/.ssh/id_rsa.pub)"
export TF_LOG='TRACE'
export TF_LOG_PATH='terraform.log'
EOF
```

Create a VPC for the image build:

```bash
source secrets.sh
pushd vpc
terraform init
terraform apply
popd
```

Build the image:

```bash
source secrets.sh
CHECKPOINT_DISABLE=1 PACKER_LOG=1 PACKER_LOG_PATH=ubuntu.init.log \
  packer init .
CHECKPOINT_DISABLE=1 PACKER_LOG=1 PACKER_LOG_PATH=ubuntu.log \
  packer build -only=amazon-ebs.ubuntu -on-error=abort -timestamp-ui .
```

**NB** When packer fails you might have to manually delete the created
resources, e.g., EC2 instance, EC2 AMI, EC2 snapshot, EC2 key pair, and
VPC security group.

Destroy the image build VPC:

```bash
pushd vpc
terraform destroy
popd
```

Create the example terraform environment that uses the created image:

```bash
pushd example
terraform init
terraform apply
```

At VM initialization time [cloud-init](https://cloudinit.readthedocs.io/en/latest/index.html) will run the `example/provision-app.sh` script to launch the example application.

After VM initialization is done (check the instance system log for cloud-init entries), test the `app` endpoint:

```bash
while ! wget -qO- "http://$(terraform output --raw app_ip_address)/test"; do sleep 3; done
```

And open a shell inside the VM:

```bash
ssh "ubuntu@$(terraform output --raw app_ip_address)"
cloud-init status --long --wait
tail /var/log/cloud-init-output.log
cat /etc/machine-id
id
df -h
wget -qO- localhost/try
systemctl status app
journalctl -u app
sudo iptables-save
sudo ip6tables-save
sudo ec2metadata
systemctl status snap.amazon-ssm-agent.amazon-ssm-agent
journalctl -u snap.amazon-ssm-agent.amazon-ssm-agent
sudo ssm-cli get-instance-information
sudo ssm-cli get-diagnostics
sudo docker info
sudo docker ps
sudo docker run --rm hello-world
exit
```

Test recreating the EC2 instance:

```bash
terraform destroy -target aws_instance.app
terraform apply
```

Destroy the example terraform environment:

```bash
terraform destroy
popd
```

Destroy the created AMI and associated snapshots:

```bash
image_id="$(aws ec2 describe-images \
  --owners self \
  --filters "Name=name,Values=$PKR_VAR_image_name" \
  --query "Images[*].ImageId" \
  --output text)"
snapshot_ids="$(aws ec2 describe-images \
  --image-ids "$image_id" \
  --query "Images[*].BlockDeviceMappings[*].Ebs.SnapshotId" \
  --output text)"
aws ec2 deregister-image \
  --image-id "$image_id"
for snapshot_id in $snapshot_ids; do
  aws ec2 delete-snapshot \
    --snapshot-id "$snapshot_id"
done
```

List this repository dependencies (and which have newer versions):

```bash
GITHUB_COM_TOKEN='YOUR_GITHUB_PERSONAL_TOKEN' ./renovate.sh
```
