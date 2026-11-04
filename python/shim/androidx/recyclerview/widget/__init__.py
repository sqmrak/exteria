"""androidx.recyclerview.widget: the class exists so a plugin can test for it, the app's own lists are not reachable"""

from android.view import ViewGroup


class RecyclerView(ViewGroup):
    pass
