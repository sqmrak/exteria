"""java.util as far as plugins reach it: the collections are python ones with the java method names added"""


class ArrayList(list):
    def add(self, *args):
        if len(args) == 2:
            self.insert(args[0], args[1])
        else:
            self.append(args[0])
        return True

    def get(self, index):
        return self[index]

    def size(self):
        return len(self)

    def isEmpty(self):
        return not self

    def clear(self):
        del self[:]

    def contains(self, item):
        return item in self

    def toArray(self):
        return list(self)


class HashMap(dict):
    def put(self, key, value):
        previous = self.get(key)
        self[key] = value
        return previous

    def containsKey(self, key):
        return key in self

    def size(self):
        return len(self)

    def remove(self, key):
        return self.pop(key, None)

    def keySet(self):
        return ArrayList(self.keys())

    def values(self):
        return ArrayList(dict.values(self))


class Locale:
    @staticmethod
    def getDefault():
        return Locale()

    def getLanguage(self):
        return "en"
