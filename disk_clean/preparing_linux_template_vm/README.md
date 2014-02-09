Dan over at Bashing Linux [has a good post ](http://bashinglinux.wordpress.com/2013/03/23/creating-a-puppet-ready-image-centosfedora/ "creating-a-puppet-ready-image-centosfedora")on what he does to prep his template VMs for use with Puppet. He’s inspired me to share how I prepare my Linux VMs to become a template. He’s got a few steps I don’t have, mainly to prep for Puppet, and I have a few steps he doesn’t have. One big difference is that I don’t prepare my template images for a particular configuration management system, but instead bootstrap them once they’re deployed. Why? I use my templates for a variety of things, and sometimes the people who end up with the VMs don’t want my management systems on them. It also means I have to handle some of what he does in his prep script via the configuration management system, but that’s just fine. I’d actually rather do it that way because it helps me guarantee the state of the system. Not saying he’s wrong, he’s got different problems to solve than I do.

You can do this in full multiuser — runlevel 3 — or in single-user by issuing an “init 1″ and waiting for all the processes to stop. I wouldn’t do any of this in runlevel 5, with full X Windows running. In fact, I really don’t suggest installing X Windows at all on VMs unless you really, really need it for some reason… but that’s a whole different topic. I’d also suggest taking a snapshot of your template prior to trying any of this out. As Lenin said, “Trust, but verify.”

# Step 1: Clean out yum.#

    /usr/bin/yum clean all

Yum keeps a cache in /var/cache/yum that can grow quite large, especially after applying patches to the template. For example, the host where my blog resides has 275 MB of stuff in yum’s cache right now, just from a few months of incremental patching. In the interest of keeping my template as small as possible I wipe this.

#Step 2: Force the logs to rotate.#

    /usr/sbin/logrotate –f /etc/logrotate.conf
    /bin/rm –f /var/log/*-???????? /var/log/*.gz

Starting fresh with the logs is nice. It means that you don’t have old, irrelevant log data on all your cloned VMs, and it also means that your template image is smaller. Change out the “rm” command for one that matches whatever your logrotate renames files as. Also, if you get really, really bored it’s fun to look at the old log data people leave on virtual appliances. Lots of leaked information there.

#Step 3: Clear the audit log & wtmp.#

    /bin/cat /dev/null > /var/log/audit/audit.log
    /bin/cat /dev/null > /var/log/wtmp

Again, might as well clear the audit & login logs. This whole /dev/null business is also a trick that lets you clear a file without restarting the process associated with it, useful in many more situations than just template-building.

#Step 4: Remove the udev persistent device rules.#

    /bin/rm -f /etc/udev/rules.d/70*

I have a whole post on this, “Why Does My Linux VM’s Virtual NIC Show Up as eth1?” This is how I’ve chosen to deal with the problem.

#Step 5: Remove the traces of the template MAC address and UUIDs.#

    /bin/sed -i ‘/^\(HWADDR\|UUID\)=/d’ /etc/sysconfig/network-scripts/ifcfg-eth0

This is a corollary to step 4, just removing unique identifiers from the template so the cloned VM gets its own. Thanks to Ed in the comments for the reminder about sed. You can also change the “-i” to “-i.bak” if you wished to keep a backup copy of the file.

#Step 6: Clean /tmp out.#

    /bin/rm –rf /tmp/*
    /bin/rm –rf /var/tmp/*

Under normal, non-template circumstances you really don’t ever want to run rm on /tmp like this. Use tmpwatch or any manner of safer ways to do this, since there are attacks people can use by leaving symlinks and whatnot in /tmp that rm might traverse (“whoops, I don’t have an /etc/passwd anymore!”). Plus, users and processes might actually be using /tmp, and it’s impolite to delete their files. However, this is your template image, and if there are people attacking your template you should reconsider how you’re doing business. Really.

#Step 7: Remove the SSH host keys.#

    /bin/rm –f /etc/ssh/*key*

If you don’t do this all your VMs will have all the same keys, which has negative security implications. It’s also annoying to fix later when you’ve realized you’ve deployed a couple of years of VMs and forgot to do this in your prep script. Not that I would know anything about that. Nope.

#Step 8: Remove the root user’s shell history#

   /bin/rm -f ~root/.bash_history
   unset HISTFILE

This good idea is courtesy of Jonathan Barber, from the comments below. No sense in keeping this history around, it’s irrelevant to the cloned VM.

#Step 9: Zero out all free space, then use storage vMotion to re-thin the VM.#
	
	#!/bin/sh
	
	# Determine the version of RHEL
	COND=`grep -i Taroon /etc/redhat-release`
	if [ "$COND" = "" ]; then
	        export PREFIX="/usr/sbin"
	else
	        export PREFIX="/sbin"
	fi
	
	FileSystem=`grep ext /etc/mtab| awk -F" " '{ print $2 }'`
	
	for i in $FileSystem
	do
	        echo $i
	        number=`df -B 512 $i | awk -F" " '{print $3}' | grep -v Used`
	        echo $number
	        percent=$(echo "scale=0; $number * 98 / 100" | bc )
	        echo $percent
	        dd count=`echo $percent` if=/dev/zero of=`echo $i`/zf
	        /bin/sync
	        sleep 15
	        rm -f $i/zf
	done
	
	VolumeGroup=`$PREFIX/vgdisplay | grep Name | awk -F" " '{ print $3 }'`
	
	for j in $VolumeGroup
	do
	        echo $j
	        $PREFIX/lvcreate -l `$PREFIX/vgdisplay $j | grep Free | awk -F" " '{ print $5 }'` -n zero $j
	        if [ -a /dev/$j/zero ]; then
	                cat /dev/zero > /dev/$j/zero
	                /bin/sync
	                sleep 15
	                $PREFIX/lvremove -f /dev/$j/zero
	        fi
	done

This script is partly ripped off from someone on the Internet who didn’t have a copyright note in their work (and we’ve lost track of the source – if it’s yours leave me a comment), and partly the work of my team. It basically fills each filesystem to 98% of full with the output of /dev/zero, as well as creating a logical volume to zero out the unused space in the volume groups. Why do this? Well, if you storage vMotion the template VM to another array, or to another datastore on an array without VAAI, and you specify thin provisioning, the software datamover will suck all the zeroes back out of the image, and it’ll be as small as possible. Keep in mind you can’t do this within an array using VAAI, because under VAAI the array does the copying, and the zero-sucking magic is only in the software datamover at the ESXi level. Just move it to a local disk and back to your array if that’s the case. This is also cool if you have storage that deduplicates, too, like NetApp arrays.

Why only to 98%? That way you can run it on operational VMs and it lessens the chance of causing something to crash because you filled the filesystem. :) On the templates you can probably push it to 100%, just adjust the math in bc.

Keep in mind that by writing zeroes to the free space you effectively un-thin the disks, so make sure you have enough space available in your datastore.

So that’s my prep routine. It relies heavily on keeping the rest of the VM clean, and only cleans up what we can’t avoid sullying. What else am I missing here? Leave me a comment!

引自：[Preparing Linux Template VMs](http://lonesysadmin.net/2013/03/26/preparing-linux-template-vms/)