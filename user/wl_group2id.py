import requests
import xmltodict
import sys


def steamid64_to_steamid(steamid64):
    steamid64 = int(steamid64)
    account_id = (steamid64 - 76561197960265728) & 0xFFFFFFFF
    y = account_id & 1
    z = (account_id - y) >> 1
    return f"STEAM_1:{y}:{z}"


def fetch_and_save_member_ids(group_url_name):
    url = f"https://steamcommunity.com/{group_url_name}/memberslistxml/?xml=1"

    response = requests.get(url)
    if response.status_code != 200:
        raise Exception(f"Error fetching data: {response.status_code}")

    data_dict = xmltodict.parse(response.content)

    member_ids = data_dict["memberList"]["members"]["steamID64"]
    
    existing_ids = set()
    try:
        with open(f"{txt_name}.txt", "r") as file:
            for line in file:
                line = line.strip()
                if line and not line.startswith(';'):
                    steamid = line.split(';')[0].strip()
                    if steamid and steamid.startswith('STEAM_'):
                        existing_ids.add(steamid)
    except FileNotFoundError:
        pass
    
    new_steamids = []
    for steamid64 in sorted(member_ids):
        steamid = steamid64_to_steamid(steamid64)
        if steamid not in existing_ids:
            new_steamids.append(steamid)
    
    if new_steamids:
        with open(f"{txt_name}.txt", "a") as file:
            for steamid in new_steamids:
                file.write(f"{steamid}\n")
        print(f"Added {len(new_steamids)} new SteamIDs")
    else:
        print("No new SteamIDs to add")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python3 list_members.py <txt_file_name> <groups/group_url or gid/group_id>")
        sys.exit(1)
    txt_name = sys.argv[1]
    group_url_name = sys.argv[2]
    fetch_and_save_member_ids(group_url_name)
    print(f"Member IDs have been saved to {txt_name}.txt")
