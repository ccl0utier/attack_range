
data "aws_ami" "latest-windows-server-2016" {
  count       = var.config.windows_domain_controller == "1" ? 1 : 0
  most_recent = true
  owners      = ["801119661308"] # Canonical

  filter {
    name   = "name"
    values = [var.config.windows_domain_controller_os]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}


resource "aws_instance" "windows_domain_controller" {
  count         = var.config.windows_domain_controller == "1" ? 1 : 0
  ami           = data.aws_ami.latest-windows-server-2016[count.index].id
  instance_type = var.config.windows_domain_controller_zeek_capture == "1" ? "m5.2xlarge" : var.config.instance_type_ec2
  key_name = var.config.key_name
  subnet_id = var.ec2_subnet_id
  private_ip = var.config.windows_domain_controller_private_ip
  vpc_security_group_ids = [var.vpc_security_group_ids]
  tags = {
    Name = "ar-win-dc-${var.config.range_name}-${var.config.key_name}"
  }
  user_data = <<EOF
<powershell>
$admin = [adsi]("WinNT://./Administrator, user")
$admin.PSBase.Invoke("SetPassword", "${var.config.attack_range_password}")
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Url = 'https://raw.githubusercontent.com/ansible/ansible/devel/examples/scripts/ConfigureRemotingForAnsible.ps1'
$PSFile = 'C:\ConfigureRemotingForAnsible.ps1'
Invoke-WebRequest -Uri $Url -OutFile $PSFile
C:\ConfigureRemotingForAnsible.ps1
</powershell>
EOF

  provisioner "remote-exec" {
    inline = ["echo booted"]

    connection {
      type     = "winrm"
      user     = "Administrator"
      password = var.config.attack_range_password
      host     = aws_instance.windows_domain_controller[count.index].public_ip
      port     = 5986
      insecure = true
      https    = true
      timeout  = "10m"
	}
  }

  provisioner "local-exec" {
    working_dir = "../../../ansible"
    command = "ansible-playbook -i '${aws_instance.windows_domain_controller[count.index].public_ip},' playbooks/windows_dc.yml --extra-vars 'splunk_indexer_ip=${var.config.splunk_server_private_ip} ansible_user=Administrator ansible_password=${var.config.attack_range_password} win_password=${var.config.attack_range_password} splunk_uf_win_url=${var.config.splunk_uf_win_url} win_sysmon_url=${var.config.win_sysmon_url} win_sysmon_template=${var.config.win_sysmon_template} splunk_admin_password=${var.config.attack_range_password} splunk_stream_app=${var.config.splunk_stream_app} s3_bucket_url=${var.config.s3_bucket_url} win_4688_cmd_line=${var.config.win_4688_cmd_line} verbose_win_security_logging=${var.config.verbose_win_security_logging} key_name=${var.config.key_name} install_red_team_tools=${var.config.install_red_team_tools} install_aurora_agent=${var.config.install_aurora_agent} aurora_agent_url=${var.config.aurora_agent_url} aurora_agent_license=${var.config.aurora_agent_license} prelude=${var.config.prelude} windows_domain_controller_run_badblood=${var.config.windows_domain_controller_run_badblood} '"
  }

}

resource "aws_eip" "windows_server_ip" {
  count    = var.config.windows_domain_controller == "1"  && var.config.use_elastic_ips == "1" ? 1 : 0
  instance = aws_instance.windows_domain_controller[0].id
}
