# processors/__init__.py
# This file makes 'processors' a Python package.
# All processor functions are imported here for convenience.

from .input_validation import validate_input
from .background_removal import remove_background
from .cropping import detect_product_bounds, auto_crop
from .background_canvas import place_on_clean_background, place_on_ecommerce_canvas
from .lighting import improve_lighting, correct_white_balance, sharpen_image
from .image_output import resize_image, save_image
