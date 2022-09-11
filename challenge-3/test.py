dict = {
    "a":"1",
    "b":{"d": {"e": {"c": "6"}}},
    "c":"3",
    "d":{"x": {"y": {"z": "7"}}},
    "p": {"s": "10", "t": "11"},
    "w":{"r":"12", "g": "13","h": {"a": "14"}},
}

values = []

def fill_values(dict):
    for k in dict.keys():
        val = dict[k]
        val_type = type(val).__name__
        if (val_type == "dict"):
            dict_new = val
            fill_values(dict_new)
        else:
            values.append(val)
            
def find_values(key, dict):
    for k in dict.keys():
        val = dict[k]
        val_type = type(val).__name__
        if(val_type == "dict"):
            dict_new = val
            if (k == key):
                fill_values(dict_new)
            else:
                find_values(key,dict_new)
        else:
            if (k == key):
                values.append(val)
                
find_values("w", dict)
print(values)
        
