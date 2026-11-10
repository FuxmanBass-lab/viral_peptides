class NetsurfpException(Exception):
    pass

class NetsurfpValueError(NetsurfpException, ValueError):
    pass
