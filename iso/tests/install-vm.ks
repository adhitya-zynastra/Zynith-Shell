# iso/tests/install-vm.ks — the automated installation test for iso/test-vm.sh. NOT part of the image.
#
# It ERASES /dev/vda: in the test VM that is the blank virtual disk made by `iso/test-vm.sh install`, and nothing
# else. Never use it on real hardware. Run inside the live test VM:
#   sudo liveinst --kickstart=/tmp/install-vm.ks --cmdline
#
# The serial console on the installed system and the test account exist only so the test can log in and check it.
text
lang en_US.UTF-8
keyboard --vckeymap=us --xlayouts='us'
timezone UTC --utc
ignoredisk --only-use=vda
zerombr
clearpart --all --initlabel --drives=vda
autopart --type=btrfs
bootloader --location=mbr --boot-drive=vda --append="console=tty0 console=ttyS0,115200"
rootpw --lock
user --name=tester --groups=wheel --password=zynith-test --plaintext
selinux --enforcing
firewall --enabled --service=mdns
poweroff
