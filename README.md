teleporter
==========

Teleporter is a hot and cold migration tool to move servers and disks to Openstack Image Service (Glance)

# Teleporter
Teleporter is a hot and cold migration tool developed by [www.stackops.com](http://www.stackops.com) to move servers and disks to Openstack Image Service (Glance) of the StackOps Platform. This tools can be used as a cold or hot migration service. It can run inside a running VM

## Why Teleporter?
Most of the tools out there are looks really cool but when you try to migrate an existing service to Cloud A to Cloud B you realize that they miss the point: they only migrate the most basic stuff but forget about the tiny little details that locks you inside a Cloud platform.

The approach of Teleporter is different: it moves the disk as a whole. The root disk becomes a Golden image, and that Golden image is what you deploy in the StackOps Cloud

## How to use it
Teleporter it is pretty straight forward. You just need a Linux Operating System with dd and curl installed with access to the net.

Execute the following command:
***
`curl -L goo.gl/3XmHG4 | sudo sh -s -- STACKOPS_USERNAME STACKOPS_PASSWORD STACKOPS_TENANT <image-name> <device-name>`
***

Once executed, the tool will dump the /dev/\<device-name\> device or /dev/sda by default to your [stackops](www.stackops.com) Glance account automatically. This process can take several hours since you are moving gigabytes of information, and can be error prone if your network is not very reliable.

# Cloud Tested

## Amazon Web Services EC2

| Image | Did it work? | Post installation notes |
|-------|--------------|-------------------------|
| ubuntu 12.04.4 64bit Server Paravirtual | Yes | No |

## Digital Ocean

| Image | Did it work? | Post installation notes |
|-------|--------------|-------------------------|
| ubuntu 12.04.4 Server 64bit | Yes | Network is static. Should be modified to dhcp |

## Google Cloud Engine

| Image | Did it work? | Post installation notes |
|-------|--------------|-------------------------|
| Debian 7 64bit | Yes | * Changed root password |
|| | * Deleted folder /usr/share/google |
|| | * Enabled tty in /etc/inittab |

# Frequently asked questions

## Dumping a full disk needs a lot of extra space. I don't have it in my VM.
You don't need it. Teleporter does not use a buffer disk, it stores the information right into our OpenStack Image repository. It can even work with a Read Only file system.

## Can I run Teleporter inside my running VMs?
Yes you can. If your VMs does not write data to disk you can do it safely. If your VMs write data to disk, I recommend to change the runlevel in such a way you don't damage your data.

## Sounds like magic. Can it work with any Virtual Machine?
No, it can't, because this is not magic. It's just a little tool that tries to alleviate the pain of changing to a new Cloud Provider.

## Can I use Teleporter inside a physical server?
Sure. Just keep in mind that you will need some drivers that may be they aren't installed in your Operating System. 

## Can I use Teleporter inside a classic Virtual Machine?
Sure. Just keep in mind that you will need some drivers that may be they aren't installed in your Operating System. 

## What is the best way to use Teleporter?
Ideally speaking Teleporter should be executed from a Recovery Distro like Knoppix or Clonezilla. But you can launch it from the live Operating System with caution.

## I have tried the tool inside my server but it says that my Operating System is not supported!
Send us a request with your Operating system and we will change the tool. We try to add it to the tool

## What is the future of the tool?
In order to have a fully running VM inside our Cloud there are some post-installations steps to do. We would like to automate them and have a tidy virtual server at the end of the process.



 
