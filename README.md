# Readme

A CloudFormation template for launching a Minecraft Server on AWS using Spot Instances.

## Rationale

Ideally, I'd like to host a Minecraft server on AWS without spending >$40 per month. Spot instances are a great way to save costs, but are vunerable to interruptions due to outbids and demand.

But what if we built a system that can handle such interruptions gracefully? As long as players are ok with the rare restart, we could host a server that provides great performance at a fifth of the cost.

## How to Use

### Prerequistes

This setup only works on one Availability Zone (AZ). So before starting, make sure to restrict your operations to one AZ.

* Prepare a key pair in case you want SSH access to your machine.
* Have a Elastic IP (EIP) ready to be assigned, with a Name tag of 'minecraft-server-ip'. If you wish to change this, see the relevant code under the `user data` section of the instance profile.
* Have a standalone EBS volume, with a Name tag of '\minecraft'. If you wish to change this, see the relevant code under the `user data` section of the instance profile.

You'll also need to install the aws cli on your operating system.


### How do I run this???

*If you haven't read through the prerequistes section above, go and make sure those steps are satisfied. Then come back and read through the rest of this section.*

Firstly, I'd recommend creating a seperate profile using the aws cli specifically for the purpose of this minecraft server. It'll stay seperate from your default settings, especially if you're trying to optimize across different regions that are not necessarily your default region. Make sure this profile can access your user account and that it has a default region defined.

Then, prepare to run this command in your terminal:

``` bash
aws cloudformation deploy --template-file minecraft-server.yaml --stack-name minecraft-server --parameter-overrides keyName=$KEY_NAME AZ=$MY_AZ --profile minecraft --capabilities CAPABILITY_NAMED_IAM
```

There are several things to unpack here.

* Our master template file is `minecraft-server.yaml`. Make sure to run this command in the same folder as this file. (Or change the path here to point to `minecraft-server.yaml`)
* I chose my CloudFormation stack name to be 'minecraft-server'. This name is arbritary.
* For parameters, we have our key pair name and availability zone (ex. 'us-east-1c'). Make sure your key pair exists on the region on which we are executing this stack.
* My aws cli profile 'minecraft' contains a different region than my default so I use it here. Feel free to remove this flag if both regions are the same on your setup.



### Detailed Description

This architecture of this template is straightforward:

1. Create two security groups, one for SSH access and the other for the standard Minecraft ports.
2. Create the EC2 Launch Template-- which will provide the basis for our server.
3. Create two roles; one for the Spot Fleet operations, and the other for the server instance permissions. In particular, the server instance is going to be responsible for attaching the EIP and EBS volume during its initialization step.
4. Create the Spot Fleet, which will launch only one Spot instance, prioritized by 'capacity' (choose the instance type that is least likely to be interrupted). This structure will use the Launch Template and role created in previous steps.
5. After deploying the Spot Fleet, the single EC2 instance will be launched and will perform some tasks during its initialization phase. Here, it will self-attach the EBS volume and EIP and prepare the setup for launching the server. Refer to the `init.sh` script for details.
6. If a termination notice is given to the Spot instance, the timer service installed on the service will trigger a shutdown for the machine. By default, the server gives 60 seconds for players to prepare for the shutdown. After which, the instance will be terminated, and the steps given in Step 5 will restart again on a new instance. Since our game data is stored on a seperate EBS volume, we can simply resume playing after this interruption.

### Development Notes

I do all the development in `minecraft-server.pre.yaml` (notice the `.pre.yaml` extension). The reasons for this are:
* I like to have some semblance of modularity, meaning I like to polish the user data script as a seperate file (`init.sh`) rather than cannibalizing it in the cloudformation file.
* I use [`cfn-include`](https://github.com/monken/cfn-include) to preprocess the `.pre.yaml` file so I can utilize its `Include` function for the reason listed above.

Once I am ready to deploy the changes, I run `cfn-include -y minecraft-server.yaml > minecraft.yaml` to process the new changes. If that is successful, I then run the command using the aws cli written in the `How to Use` section.
