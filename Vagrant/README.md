# TheHive / Cortex VM

## Introduction

**This is an unofficial build.** 
TheHive Project maintains the original training virtual machine (OVA) containing TheHive, Cortex as well as Cortex analyzers and responders with all their dependencies included, and ElasticSearch. The training VM runs Ubuntu 18.04.3 LTS with Oracle JRE 8.

This is an updated training VM containing the the following components

- Elasticsearch 6.8
- TheHive 3.4.0
- Cortex 3.0.0
- Cortexutils 2.0.0  
- TheHive4py 1.6.0
- Cortex4py 2.0.1
- Report templates
- All Docker based analysers and responders

**Warnings**
- The resulting virtual machine is not designed for production, it is designed as a quick way to test functionality and to see if this product is suitable for your requirements.

## Accounts and Access

Default user accounts and URL's for this VM are as follows.  

Ubuntu user account: `vagrant` / `vagrant`  
TheHive URL: `http://w.x.y.z:9000`  
Cortex URL: `http://w.x.y.z:9001`  

Cortex SuperAdmin account: `admin` / `thehive1234`  
Cortex TrainingAdmin account: `thehive` / `thehive1234`  

## Building this environment

This environment was built using VirtualBox on Ubuntu and can be built with the vagrant script.  At this time building this is only supported in Ubuntu / Debian based systems.  Requirements as follows:

- [Virtual Box](<https://www.virtualbox.org/wiki/Downloads>)
- [Vagrant](<https://www.vagrantup.com/downloads.html>)
- Internet connection

Create a new folder and clone this repository
Use `vagrant up` to build the environment
Use `vagrant destroy` to tear it down

## Integration with MISP

This build does not contain MISP.  The MISP VM can be downloaded from the [Circl.lu site](<https://www.circl.lu/misp-images/latest/>).  Integrating it is a matter of creating a user in MISP, obtaining an auth key, updating `/opt/thehive/conf/application.conf` and restarting TheHive service.

## Notes

- This is a work in progress, but its functional.  
- All the user accounts and API keys have been pre-configured.
- As Docker is being used for the Analysers and Responders, there is a delay the first time they are executed as the container is downloaded.  This is normal and subsequent executions of the same analyser or responder should return quicker.
- Upon first load of TheHive you will need to perform a `database update` and which will prompt you to create an `admin` account.

## Todo

- Inclusion of more error checking, handling and verification in the vagrant/shell script
- Create build script for Windows based hosts
