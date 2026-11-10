import re

def get_valid_filename(s):
    """ Returns a valid filename from string """
    s = str(s).strip().replace(' ', '_')
    return re.sub(r'(?u)[^-\w.]', '', s)
