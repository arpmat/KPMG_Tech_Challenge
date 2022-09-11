#!/usr/bin/python3
import boto3
import json
import flatdict

client = boto3.client('ec2')
dict_new = client.describe_instances()
json = json.dumps(dict_new, indent=4, sort_keys=True, default=str)
print(json)
print("############")

def getvalues(key, dict):
    for reservation in dict["Reservations"]:
        for instance in reservation["Instances"]:
            for k in instance.keys():
                if (k == key):
                    print(instance[k])

getvalues("NetworkInterfaces", dict_new)
