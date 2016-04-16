# Powershell Cmdlet for writing data to Fluentd


## Overview

write-fluentd is recived from another cmdlet output by pipe, and post to fluentd server

## Installation

Download "write-fluentd.ps1" and use with dot operator

```
. \write-fluentd.ps1
```

## Usage

```
Do-SomeCmdlet | write-fluentd -server 'http://fluentd-server:9880/' `
                              -tag    'net.somecmdlet' `
                              -text   'location'
```

### -server

Protocol (http or https), fluentd server FQDN, and port number

### -tag

fluentd tag

### -text

specify the fields for text properties (not value fields) by String Array

Ex. 
    -text ('location','hostname','user')


## License
This Script is licensed according to the terms of the MIT License.

