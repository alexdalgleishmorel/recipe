"""Shared API-Lambda plumbing for the CRUD handlers (#14-#16).

This layer holds the cross-cutting concerns every API Lambda needs — caller identity
(``get_user_id``) and HTTP request/response shaping (``api``) — so the recipes, plans, and
collections handlers stay thin and consistent. Persistence lives in the ``data_access`` layer; this
layer never touches DynamoDB.
"""

from . import api
from .auth import get_user_email, get_user_id, jwt_name

__all__ = ["api", "get_user_id", "get_user_email", "jwt_name"]
