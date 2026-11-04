"""the android package of the shim. R is the id table plugins look views up by; the only view it names that exists here is none:
the views of the app itself are not reachable, so findViewById(R.id.content) answers None and a plugin that scans them does nothing"""


class R:
    class id:
        content = 16908290
