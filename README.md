# Google Cloud hook for `dehydrated`

This is a hook for the [Let's Encrypt](https://letsencrypt.org/) ACME client [dehydrated](https://github.com/lukas2511/dehydrated) (previously known as `letsencrypt.sh`) that allows you to use [Google Cloud DNS](https://cloud.google.com/dns/docs/) records to respond to `dns-01` challenges as well as uploading the certificates to [Google Cloud Platform HTTPS load balancers](https://cloud.google.com/compute/docs/load-balancing/http/). This hook requires the Google Cloud SDK (aka the gcloud command-line tool).

## Installation

```
$ cd ~
$ git clone https://github.com/lukas2511/dehydrated
$ cd dehydrated
$ mkdir hooks
$ git clone https://github.com/spfguru/dehydrated4googlecloud hooks/google-cloud
```

Make sure you have the latest version of the [Google Cloud SDK](https://cloud.google.com/sdk/downloads) installed. 

## Configuration

This hook uses the gcloud command-line tool and fascilitates the default project and account information. Check ```gcloud info``` to see, what this is set to. Also, your account needs to have "editor" permissions in the current project. This project needs to host your DNS zone for the domain (or a subdomain) you want to get a Let's Encrypt certificate for. Also, if you use the Google Cloud HTTPS load balancers, these have to be in the same project as well. Only required if you wish this hook to update the created certificates automatically. 

Also you need to change the following settings in your dehydrated config (original value commented out):
```
# Which challenge should be used? Currently http-01 and dns-01 are supported
#CHALLENGETYPE="http-01"
CHALLENGETYPE="dns-01"

# Default keysize for private keys (default: 4096)
#KEYSIZE="4096"
# Google Cloud currently only supports up to 2048 bit key length
KEYSIZE="2048"
``` 

If you use Google Cloud HTTPS load balancers, you need to align your setup of target proxies with how you create the certificates. All domains served by a target proxy have to be in the same certificate. If that is more than one, you cannot use the -d command line option of dehydrated. Instead you have to create a domains.txt file. The following example assumes you have two target proxies; one serving requests for example.com and www.example.com. And the second one serving wwwtest.example.com:

domains.txt
``` 
example.com www.example.com
wwwtest.example.com
``` 

After certificate have been created, this hook will add the newly created certificates to the Google Cloud HTTPS load balancer; no existing SSL certificates will be overwritten. In order to activate the new certificates, the so called target proxy has to point to the new certifiacte. You need to do that manually, unless your target proxy name adheres to the following naming convention:

```
https-proxy-DOMAIN-NAME
```

Where DOMAIN-NAME is the first domain name of each line in the domains.txt, having each '.' replaced by a '-'. Given the above sample domains.txt, the hook would look for https-proxy-example-com and https-wwwtest-proxy-example-com. Keep in mind that the www.example.com domain would be served from the https-proxy-example-com, thus no dedicated target proxy exists for that.

## Usage

```
$ ./dehydrated -c -t dns-01 -k 'hooks/google-cloud/hook.sh'
```

The ```-t dns-01``` part can be skipped, if you have set this challenge type in your config already. Same goes for the ```-k 'hooks/google-cloud/hook.sh'``` part, when set in the config as well.

