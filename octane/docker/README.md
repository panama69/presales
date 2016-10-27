installOctane.sh <domain> <initpassword>
- this script will start Octane, Oracel & Elastic search
- initial login id is sa@nga

downOctane.sh
- this scripts stops and removes the containers along with the volume mounts.

select-menu.sh
- script wiich provides 3 deployment options: With Data, Empty, New
- All Octane containers need to be down (it checks)
- Check if network is present before removing any folders so your data isn't deleted if you can get the image you want
- **Requires** dialog which can be installed on Ubuntu using 'sudo apt-get install dialog' and can be installed on Suse from https://software.opensuse.org/package/dialog
