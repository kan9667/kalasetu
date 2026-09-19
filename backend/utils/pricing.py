"""
Financial & Cost Floor Precision Utilities.

Enforces integer-paise calculations and ceiling bounds for artisan fair-price floors.
"""

from decimal import Decimal, ROUND_CEILING
from fastapi import HTTPException, status


def rupees_to_paise(amount: float) -> int:
    """Convert float rupees to integer paise using Decimal rounding."""
    if amount is None:
        return 0
    d = Decimal(str(amount)) * Decimal("100")
    return int(d.to_integral_value(rounding=ROUND_CEILING))


def paise_to_rupees(paise: int) -> float:
    """Convert integer paise to float rupees rounded to 2 decimal places."""
    if paise is None:
        return 0.0
    return round(float(paise) / 100.0, 2)


def calculate_cost_floor_paise(
    materials_paise: int = 0,
    labor_hours: float = 0.0,
    hourly_rate_paise: int = 5000,
    transport_paise: int = 0,
    overhead_paise: int = 0,
) -> int:
    """
    Calculate the server-authoritative cost floor in integer paise:
    floor = materials + (labor_hours * hourly_rate) + transport + overhead.
    """
    mat = Decimal(str(materials_paise or 0))
    hours = Decimal(str(labor_hours or 0.0))
    rate = Decimal(str(hourly_rate_paise if hourly_rate_paise > 0 else (5000 if hours > 0 else 0)))
    trans = Decimal(str(transport_paise or 0))
    over = Decimal(str(overhead_paise or 0))

    labor_cost = hours * rate
    total = mat + labor_cost + trans + over
    return int(total.to_integral_value(rounding=ROUND_CEILING))


def validate_price_against_floor(price_paise: int, floor_price_paise: int) -> None:
    """
    Reject any price strictly lower than the persisted cost floor.
    """
    if price_paise < floor_price_paise:
        price_rupees = paise_to_rupees(price_paise)
        floor_rupees = paise_to_rupees(floor_price_paise)
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=(
                f"Selling price (₹{price_rupees:,.2f}) cannot be below the calculated "
                f"cost floor of ₹{floor_rupees:,.2f}."
            ),
        )
