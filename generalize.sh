#!/bin/bash
set -euxo pipefail

# clean the ssh host keys.
rm -f /etc/ssh/ssh_host_*_key*

# clean packages.
apt-get -y autoremove --purge
apt-get -y clean

# reset cloud-init (and machine-id).
cloud-init clean --logs --machine-id --seed --configs all

# zero the free disk space -- for better compression of the image file.
# NB unfortunately, EC2 EBS volumes do not support fstrim as that command fails with:
#       fstrim: /: the discard operation is not supported
# # NB prefer discard/trim (safer; faster) over creating a big zero filled file
# #    (somewhat unsafe as it has to fill the entire disk, which might trigger
# #    a disk (near) full alarm; slower; slightly better compression).
# if [ "$(lsblk -no DISC-GRAN $(findmnt -no SOURCE /) | awk '{print $1}')" != '0B' ]; then
#     while true; do
#         output="$(fstrim -v /)"
#         cat <<<"$output"
#         sync && sync && sleep 15
#         bytes_trimmed="$(echo "$output" | perl -n -e '/\((\d+) bytes\)/ && print $1')"
#         # NB if this never reaches zero, it might be because there is not
#         #    enough free space for completing the trim.
#         if (( bytes_trimmed < $((200*1024*1024)) )); then # < 200 MiB is good enough.
#             break
#         fi
#     done
# else
#     dd if=/dev/zero of=/EMPTY bs=1M || true && sync && rm -f /EMPTY
# fi
