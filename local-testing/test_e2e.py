#!/usr/bin/env python3
"""
End-to-end test for flights-live-pricing stack
Requires: pip install requests
"""

import re
import sys
import time
from pathlib import Path
from typing import Optional

try:
    import requests
except ImportError:
    print("❌ requests library not found")
    print("Install with: pip install requests")
    sys.exit(1)


class Colors:
    GREEN = '\033[0;32m'
    BLUE = '\033[0;34m'
    RED = '\033[0;31m'
    YELLOW = '\033[0;33m'
    NC = '\033[0m'


def check_service_health(port: int, name: str) -> bool:
    """Check if a service is healthy"""
    try:
        response = requests.get(f"http://localhost:{port}/operations/healthcheck", timeout=2)
        if response.ok:
            print(f"  {Colors.GREEN}✓{Colors.NC} {name} is healthy")
            return True
    except Exception as e:
        print(f"  {Colors.RED}✗{Colors.NC} {name} failed: {e}")
    return False


def extract_session_id(response_text: str) -> Optional[str]:
    """Extract session_id from protobuf text format response"""
    match = re.search(r'session_id:\s*"([^"]+)"', response_text)
    return match.group(1) if match else None


def count_field(response_text: str, field_name: str) -> int:
    """Count occurrences of a field in the response"""
    return len(re.findall(f'{field_name}:', response_text))


def main():
    print("=" * 50)
    print("E2E Test: Flights Live Pricing Stack (Python)")
    print("=" * 50)
    print()

    # Configuration
    conductor_url = "http://localhost:5020"
    create_path = Path("conductor/src/test/resources/examples/proto_v1/create.pb")
    poll_path = Path("conductor/src/test/resources/examples/proto_v1/poll.pb")

    # Find the paths relative to the script location
    script_dir = Path(__file__).parent.parent  # Go up to repo root
    create_path = script_dir / create_path
    poll_path = script_dir / poll_path

    if not create_path.exists():
        print(f"{Colors.RED}✗ Create request file not found: {create_path}{Colors.NC}")
        sys.exit(1)

    if not poll_path.exists():
        print(f"{Colors.RED}✗ Poll request file not found: {poll_path}{Colors.NC}")
        sys.exit(1)

    # Step 1: Health checks
    print(f"{Colors.BLUE}[1/4] Checking service health...{Colors.NC}")
    services = [
        (5020, "conductor"),
        (5030, "fps"),
        (5050, "qrs"),
        (5040, "ic")
    ]

    all_healthy = all(check_service_health(port, name) for port, name in services)
    if not all_healthy:
        print(f"\n{Colors.RED}✗ Some services are unhealthy{Colors.NC}")
        sys.exit(1)
    print()

    # Step 2: Create search session
    print(f"{Colors.BLUE}[2/4] Creating search session...{Colors.NC}")

    with open(create_path, 'rb') as f:
        create_data = f.read()

    try:
        response = requests.post(
            f"{conductor_url}/api/v1/search/create",
            data=create_data,
            headers={
                "Content-Type": "application/x-protobuf-text-format",
                "Accept": "application/x-protobuf-text-format"
            },
            timeout=30
        )
        response.raise_for_status()
    except Exception as e:
        print(f"{Colors.RED}✗ Create request failed: {e}{Colors.NC}")
        sys.exit(1)

    create_response = response.text
    session_id = extract_session_id(create_response)

    if not session_id:
        print(f"{Colors.RED}✗ Failed to extract session_id{Colors.NC}")
        print(f"Response: {create_response[:500]}")
        sys.exit(1)

    print(f"  {Colors.GREEN}✓{Colors.NC} Session created: {session_id}")

    agent_count = count_field(create_response, "agent_status")
    itinerary_count = count_field(create_response, "itinerary_id")
    print(f"  → Agents: {agent_count}, Itineraries: {itinerary_count}")
    print()

    # Step 3: Poll for updates
    print(f"{Colors.BLUE}[3/4] Polling for live updates...{Colors.NC}")

    with open(poll_path, 'r') as f:
        poll_template = f.read()

    poll_data = poll_template.replace("{SESSION ID HERE}", session_id)

    max_polls = 5
    poll_interval = 2
    final_response = None

    for i in range(1, max_polls + 1):
        print(f"  Poll attempt {i}/{max_polls}...")

        try:
            response = requests.post(
                f"{conductor_url}/api/v1/search/poll",
                data=poll_data.encode('utf-8'),
                headers={
                    "Content-Type": "application/x-protobuf-text-format",
                    "Accept": "application/x-protobuf-text-format"
                },
                timeout=30
            )
            response.raise_for_status()
        except Exception as e:
            print(f"{Colors.RED}✗ Poll request failed: {e}{Colors.NC}")
            sys.exit(1)

        poll_response = response.text
        final_response = poll_response

        # Parse agent status
        completed_agents = poll_response.count("status: AGENT_DONE")
        pending_agents = poll_response.count("status: AGENT_PENDING")
        poll_itinerary_count = count_field(poll_response, "itinerary_id")

        print(f"    → Completed: {completed_agents}, Pending: {pending_agents}, "
              f"Itineraries: {poll_itinerary_count}")

        # Check if all agents are done
        if pending_agents == 0 and completed_agents > 0:
            print(f"  {Colors.GREEN}✓{Colors.NC} All agents completed!")
            break

        if i < max_polls:
            time.sleep(poll_interval)

    if pending_agents > 0:
        print(f"  {Colors.YELLOW}⚠{Colors.NC} Some agents still pending "
              f"(may be normal for slow partners)")
    print()

    # Step 4: Validate results
    print(f"{Colors.BLUE}[4/4] Validating results...{Colors.NC}")

    validation_failed = False

    # Validate session_id format (UUID)
    uuid_pattern = r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    if re.match(uuid_pattern, session_id):
        print(f"  {Colors.GREEN}✓{Colors.NC} session_id format is valid")
    else:
        print(f"  {Colors.RED}✗{Colors.NC} session_id is not a valid UUID: {session_id}")
        validation_failed = True

    # Validate itineraries exist
    if poll_itinerary_count > 0:
        print(f"  {Colors.GREEN}✓{Colors.NC} Received itineraries: {poll_itinerary_count}")
    else:
        print(f"  {Colors.RED}✗{Colors.NC} No itineraries returned")
        validation_failed = True

    # Validate required fields
    required_fields = ["itinerary_id", "pricing_option", "leg"]
    for field in required_fields:
        if field in final_response:
            print(f"  {Colors.GREEN}✓{Colors.NC} Response contains '{field}'")
        else:
            print(f"  {Colors.RED}✗{Colors.NC} Response missing '{field}'")
            validation_failed = True

    print()
    print("=" * 50)
    if not validation_failed:
        print(f"{Colors.GREEN}✓ E2E TEST PASSED{Colors.NC}")
        print("=" * 50)
        sys.exit(0)
    else:
        print(f"{Colors.RED}✗ E2E TEST FAILED{Colors.NC}")
        print("=" * 50)
        print("\nLast response preview:")
        print(final_response[:1000])
        sys.exit(1)


if __name__ == "__main__":
    main()
