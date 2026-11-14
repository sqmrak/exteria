"""org.telegram.tgnet.tl: the schema classes the android client groups by layer file. python cannot send a request to telegram on ios, so these
records are what a plugin builds, copies and tests against; a response never arrives as one of them"""

from java.util import ArrayList
from org.telegram.tgnet.TLRPC import _Record


class TL_stars:
    """the star gifts and the star rating, as nested classes the way the client has them (TL_stars.TL_starGift)"""

    class StarGift(_Record):
        pass

    class TL_starGift(StarGift):
        _FIELDS = {
            "flags": 0, "limited": False, "sold_out": False, "birthday": False, "require_premium": False, "resale_ton_only": False,
            "limited_per_user": False, "peer_color_available": False, "can_upgrade": False, "auction": False, "theme_available": False,
            "burned": False, "crafted": False, "id": 0, "gift_id": 0, "sticker": None, "stars": 0, "availability_remains": 0,
            "availability_total": 0, "availability_resale": 0, "convert_stars": 0, "upgrade_stars": 0, "resell_min_stars": 0,
            "first_sale_date": 0, "last_sale_date": 0, "per_user_total": 0, "per_user_remains": 0, "locked_until_date": 0,
            "title": "", "slug": "", "num": 0, "owner_id": None, "owner_name": "", "owner_address": "", "availability_issued": 0,
            "gift_address": "", "theme_peer": None, "peer_color": None, "host_id": None, "released_by": None, "background": None,
            "value_amount": 0, "value_currency": "", "value_usd_amount": 0, "resell_amount": None, "auction_slug": "",
            "gifts_per_round": 0, "offer_min_stars": 0, "auction_start_date": 0, "craft_chance_permille": 0,
        }

        def __init__(self, **fields):
            super().__init__(**fields)
            self.attributes = fields.get("attributes", ArrayList())
            self.upgrade_variants = fields.get("upgrade_variants", ArrayList())

    class StarGifts(_Record):
        pass

    class TL_starGifts(StarGifts):
        _FIELDS = {"hash": 0}

        def __init__(self, **fields):
            super().__init__(**fields)
            self.gifts = fields.get("gifts", ArrayList())
            self.chats = fields.get("chats", ArrayList())
            self.users = fields.get("users", ArrayList())

    class TL_starGiftsNotModified(StarGifts):
        pass

    class Tl_starsRating(_Record):
        _FIELDS = {"flags": 0, "level": 0, "current_level_stars": 0, "stars": 0, "next_level_stars": 0}
